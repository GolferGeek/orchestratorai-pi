/**
 * OrchestratorAI bridge for Pi.
 *
 * Three responsibilities, all deterministic (no model in the loop):
 *
 * 1. `/orchestrator start|stop|ping <json>` — a slash command the macOS app
 *    invokes over Pi RPC. `start` launches a saved pi-agents workflow by name
 *    with literal params. The root model never decides whether to run it.
 *
 * 2. Run journal — every pi-agents run event (workflow tree, node lifecycle,
 *    intermediate values, final result) is written to the on-device SQLite
 *    store at data/orchestrator.sqlite. The app reads that file; nothing is
 *    smuggled through the RPC UI channel.
 *
 * 3. `attorney_review` tool — a human-in-the-loop gate that a workflow agent
 *    can call mid-flow.
 *
 * 4. `jev_check` tool — runs a named rubric from the orchestratorai-jev
 *    library against text and returns a routed decision (pass | review |
 *    block) with calibrated answers. Pi has no MCP by design, so the extension
 *    links jev-core directly; the rubrics are the same files the MCP serves.
 *    Every evaluation is recorded in the store. It records a pending checkpoint and blocks until the
 *    attorney approves or requests changes in the app. Delegated agents run in
 *    this same project, so they load this extension and see the tool.
 */

import * as fs from "node:fs";
import * as path from "node:path";
import { randomUUID } from "node:crypto";
import { Type } from "typebox";
import { RunStore, type RunRow } from "./store";
import { JevClient, runRubric, type Rubric } from "@orchestratorai/jev-core";
import { loadRubricDir, defaultRubricDir } from "@orchestratorai/jev-core/node";

const CALLER = "orchestratorai";
const REPLY_TYPE = "orchestrator:reply";
const GATE_POLL_MS = 1500;
const GATE_MAX_WAIT_MS = 12 * 60 * 60 * 1000;

// pi-agents run-event shapes we care about (see pi-agents/src/run/events.ts).
type RunHeader = {
  id: string;
  label?: string;
  display?: string;
  source: { kind: string; workflow?: string; caller?: string };
  params?: Record<string, unknown>;
  /** Expanded flow; a saved-workflow start is a root `workflow` node carrying the params. */
  flow?: { kind?: string; name?: string; params?: Record<string, unknown> };
};
type TraceEvent = {
  type: string;
  at?: number;
  runId?: string;
  run?: RunHeader;
  path?: string;
  instance?: string;
  kind?: string;
  profile?: string;
  label?: string;
  model?: string;
  sessionFile?: string;
  value?: unknown;
  error?: string;
  status?: string;
  reason?: string;
  iteration?: number;
  agents?: number;
  message?: string;
};

// ---------------------------------------------------------------- helpers

function findProjectDir(start: string): string {
  let dir = path.resolve(start);
  while (true) {
    if (fs.existsSync(path.join(dir, ".pi", "settings.json"))) return dir;
    const parent = path.dirname(dir);
    if (parent === dir) return path.resolve(start);
    dir = parent;
  }
}

// Only node_started carries profile/label; remember them per node instance so
// later lifecycle events for the same node read the same way.
const nodeNames = new Map<string, string>();

function readableNode(event: TraceEvent): string {
  const key = `${event.runId ?? ""}:${event.instance ?? event.path ?? ""}`;
  const own = event.label ?? event.profile;
  if (own) {
    nodeNames.set(key, own);
    return own;
  }
  return nodeNames.get(key) ?? event.kind ?? "node";
}

function summarize(event: TraceEvent): string {
  switch (event.type) {
    case "run_created": {
      const workflow = event.run?.source?.workflow ?? "workflow";
      return `Started ${workflow}${event.run?.label ? ` — ${event.run.label}` : ""}`;
    }
    case "node_started":
      return `Started ${readableNode(event)}`;
    case "node_completed":
      return `Completed ${readableNode(event)}`;
    case "node_failed":
      return `Failed ${readableNode(event)}${event.error ? ` — ${event.error}` : ""}`;
    case "node_cancelled":
      return `Cancelled ${readableNode(event)}${event.reason ? ` (${event.reason})` : ""}`;
    case "node_steered":
      return `Steered ${readableNode(event)}`;
    case "node_model":
      return `Model ${event.model ?? ""} for ${readableNode(event)}`.trim();
    case "node_session":
      return `Session opened for ${readableNode(event)}`;
    case "loop_iteration":
      return `Iteration ${event.iteration ?? ""}`.trim();
    case "run_backgrounded":
      return "Workflow running in background";
    case "run_completed":
      return event.status === "completed"
        ? `Workflow completed · ${event.agents ?? 0} agent calls`
        : `Workflow ${event.status ?? "finished"}${event.error ? ` — ${event.error}` : ""}`;
    default:
      return event.type;
  }
}

function resolvePath(value: unknown, dotPath: string | undefined): unknown {
  if (!dotPath) return undefined;
  let current: unknown = value;
  for (const part of dotPath.split(".")) {
    if (typeof current !== "object" || current === null) return undefined;
    current = (current as Record<string, unknown>)[part];
  }
  return current;
}

/** Human-facing Markdown for a completed run, mirroring pi-agents' rules. */
function presentResult(value: unknown, display: string | undefined): string | undefined {
  const pinned = resolvePath(value, display);
  if (typeof pinned === "string") return pinned;
  if (typeof value === "string") return value;
  if (typeof value === "object" && value !== null) {
    const report = (value as Record<string, unknown>).report;
    if (typeof report === "string") return report;
  }
  return undefined;
}

function jsonText(value: unknown): string | undefined {
  if (value === undefined) return undefined;
  try {
    return JSON.stringify(value, null, 2);
  } catch {
    return String(value);
  }
}

function parseJsonArg(raw: string): Record<string, unknown> {
  const trimmed = raw.trim();
  if (!trimmed) return {};
  const parsed: unknown = JSON.parse(trimmed);
  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
    throw new Error("expected a JSON object");
  }
  return parsed as Record<string, unknown>;
}

function stringMap(raw: unknown): Record<string, string> {
  const out: Record<string, string> = {};
  if (typeof raw !== "object" || raw === null) return out;
  for (const [key, value] of Object.entries(raw as Record<string, unknown>)) {
    if (value === undefined || value === null) continue;
    out[key] = String(value);
  }
  return out;
}

function sleep(ms: number, signal?: AbortSignal): Promise<void> {
  return new Promise((resolve) => {
    const timer = setTimeout(done, ms);
    function done() {
      signal?.removeEventListener("abort", done);
      clearTimeout(timer);
      resolve();
    }
    signal?.addEventListener("abort", done, { once: true });
  });
}


// Raw pi-agents event-bus client. The documented channels need no import from
// the pi-agents package, which keeps this extension independent of where Pi
// installed that package.
const RUN_EVENT_CHANNEL = "pi-agents:run-event";
const RPC_REQUEST_CHANNEL = "pi-agents:rpc:request";
const RPC_REPLY_PREFIX = "pi-agents:rpc:reply:";
// pi-agents 0.21 speaks envelope protocol 2 (see pi-agents/src/protocol.ts).
const PI_AGENTS_PROTOCOL = 2;

function piAgentsBus(pi: any) {
  function request<T = any>(op: string, params?: Record<string, unknown>): Promise<T> {
    return new Promise<T>((resolve, reject) => {
      const id = randomUUID();
      const timer = setTimeout(() => {
        unsubscribe();
        reject(new Error(`pi-agents '${op}' timed out — is the pi-agents package loaded?`));
      }, 15000);
      const unsubscribe = pi.events.on(`${RPC_REPLY_PREFIX}${id}`, (raw: any) => {
        clearTimeout(timer);
        unsubscribe();
        if (raw?.success) resolve(raw.data as T);
        else reject(new Error(raw?.error ?? `pi-agents '${op}' failed`));
      });
      pi.events.emit(RPC_REQUEST_CHANNEL, { protocol: PI_AGENTS_PROTOCOL, id, caller: CALLER, op, params });
    });
  }
  return {
    start: (params: { workflow?: string; flow?: unknown; params?: Record<string, string>; label?: string; display?: string }) =>
      request<{ runId: string; warnings?: string[] }>("start", params),
    stop: (runId: string) => request("stop", { runId }),
    onRunEvent: (handler: (event: unknown) => void) =>
      pi.events.on(RUN_EVENT_CHANNEL, (envelope: any) => {
        if (envelope?.event) handler(envelope.event);
      }),
  };
}

// ----------------------------------------------------------------- resume

/**
 * Top-level step index for a node path. A saved-workflow run's root is a
 * `workflow` node whose body is the sequence, so steps are `$.body.steps[i]`.
 * A resumed run is an inline sequence, so steps are `$.steps[k]` and map back
 * to the original index via the run's resume offset.
 */
function topLevelStepIndex(path: string | undefined, resumeOffset: number): number | undefined {
  if (!path) return undefined;
  let m = /^\$\.body\.steps\[(\d+)\]$/.exec(path);
  if (m) return Number(m[1]);
  m = /^\$\.steps\[(\d+)\]$/.exec(path);
  if (m) return Number(m[1]) + resumeOffset;
  return undefined;
}

/** pi-agents interpolates `{...}` in strings; stored values must be re-submitted literally. */
function escapeBraces(value: unknown): unknown {
  if (typeof value === "string") return value.replace(/\{/g, "{{").replace(/\}/g, "}}");
  if (Array.isArray(value)) return value.map(escapeBraces);
  if (value && typeof value === "object") return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, escapeBraces(v)]));
  return value;
}

/** Inline flows carry no params, so `{params.x}` in the remaining steps is replaced with the literal value. */
function substituteParams(node: unknown, params: Record<string, string>): unknown {
  if (typeof node === "string") {
    return node.replace(/\{params\.([A-Za-z0-9_-]+)\}/g, (whole, name: string) =>
      name in params ? (escapeBraces(params[name]) as string) : whole,
    );
  }
  if (Array.isArray(node)) return node.map((n) => substituteParams(n, params));
  if (node && typeof node === "object") {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(node)) {
      // Expansion-derived fields cannot be author-supplied; pi-agents re-expands workflow refs by name.
      if (k === "body" && (node as { kind?: string }).kind === "workflow") continue;
      if (k === "paramDefs") continue;
      out[k] = substituteParams(v, params);
    }
    return out;
  }
  return node;
}

/**
 * Build the flow that finishes an interrupted run: `value` nodes re-bind every
 * completed top-level step's result (an attorney override wins over the stored
 * value), then the remaining steps run unchanged. A step that was partly done
 * (a loop mid-iteration, a gate mid-wait) re-runs whole; gates are idempotent.
 */
function buildResumeFlow(run: RunRow, completed: Map<number, unknown>, overrides: Map<number, unknown>) {
  if (!run.flow_json) throw new Error("run has no stored flow (started before resume support)");
  const flow = JSON.parse(run.flow_json) as { kind: string; body?: { kind: string; steps?: unknown[] }; steps?: unknown[] };
  const root = flow.kind === "workflow" ? flow.body : flow;
  if (!root || root.kind !== "sequence" || !Array.isArray(root.steps)) throw new Error("resume supports sequence-rooted workflows");
  const steps = root.steps as Array<{ as?: string }>;
  let resumeAt = 0;
  while (resumeAt < steps.length && (overrides.has(resumeAt) || completed.has(resumeAt))) resumeAt++;
  if (resumeAt >= steps.length) throw new Error("nothing to resume: every step already completed");
  const params = JSON.parse(run.params_json) as Record<string, string>;
  const rebinds = [];
  for (let i = 0; i < resumeAt; i++) {
    const as = steps[i].as;
    if (!as) continue;
    const value = overrides.has(i) ? overrides.get(i) : completed.get(i);
    rebinds.push({ kind: "value", value: escapeBraces(value), as, label: `resume:${as}` });
  }
  const remaining = steps.slice(resumeAt).map((st) => substituteParams(st, params));
  // In the rebuilt flow, `$.steps[k]` is original step `k - rebinds.length + resumeAt`.
  const resumeOffset = resumeAt - rebinds.length;
  return { flow: { kind: "sequence", steps: [...rebinds, ...remaining] }, resumeAt, resumeOffset, display: run.display ?? undefined };
}

// -------------------------------------------------------------- extension

export default function orchestrator(pi: any) {
  let store: RunStore | undefined;
  let projectDir: string | undefined;
  const headers = new Map<string, RunHeader>();
  const piToLocal = new Map<string, string>();
  const agents = piAgentsBus(pi);

  function openStore(cwd: string): RunStore {
    if (store) return store;
    projectDir = findProjectDir(cwd);
    store = new RunStore(projectDir);
    return store;
  }

  function reply(payload: Record<string, unknown>) {
    pi.sendMessage(
      { customType: REPLY_TYPE, content: JSON.stringify(payload), display: true },
      { triggerTurn: false },
    );
  }

  // Resolve (or lazily create) the local run row for a pi-agents run id.
  function localRunFor(event: TraceEvent, db: RunStore): RunRow | undefined {
    const piRunId = event.type === "run_created" ? event.run?.id : event.runId;
    if (!piRunId) return undefined;
    const cached = piToLocal.get(piRunId);
    if (cached) return db.getRun(cached);

    let row = db.findRunByPiId(piRunId);
    if (!row && event.type === "run_created" && event.run) {
      const declared = event.run.params?.run_id ?? event.run.flow?.params?.run_id;
      if (typeof declared === "string" && declared) row = db.getRun(declared);
      if (!row) {
        // A run started from the TUI (or another extension): journal it too.
        row = db.createRun({
          id: piRunId,
          workflow: event.run.source.workflow ?? event.run.flow?.name ?? "inline",
          title: event.run.label ?? event.run.source.workflow ?? "Workflow run",
          params: stringMap(event.run.params ?? event.run.flow?.params),
        });
      }
      db.markStarted(row.id, piRunId);
      row = db.getRun(row.id);
    }
    if (row) piToLocal.set(piRunId, row.id);
    return row;
  }

  pi.on("session_start", (_event: unknown, ctx: any) => {
    openStore(ctx.cwd);
    if (ctx?.hasUI) ctx.ui.setStatus("orchestratorai", "OrchestratorAI journal active");
  });

  // ------------------------------------------------ live text (child side)
  // Delegated agents run this same extension. Each one streams what it is
  // writing into run_progress keyed by its session file; the parent journals
  // that file in the node_session event, so the app can join the two. Every
  // stream event carries `partial` (the assistant message so far), and the
  // deliverable arrives as the arguments of the pi_agents_submit_result tool
  // call, not as text - so both are rendered. Throttled to ~4 writes/s.
  let liveSessionFile: string | undefined;
  let livePending: string | undefined;
  let liveFlushTimer: ReturnType<typeof setTimeout> | undefined;

  function renderPartial(message: any): string {
    const parts: string[] = [];
    for (const c of message?.content ?? []) {
      if (c?.type === "text" && typeof c.text === "string") parts.push(c.text);
      else if (c?.type === "toolCall") {
        const args = c.arguments ?? {};
        if (c.name === "pi_agents_submit_result") {
          const result = args.result ?? args.error;
          parts.push(typeof result === "string" ? result : JSON.stringify(result ?? args, null, 2));
        } else {
          parts.push(`[${c.name}] ${JSON.stringify(args).slice(0, 200)}`);
        }
      }
    }
    return parts.join("\n\n");
  }
  function flushLive() {
    liveFlushTimer = undefined;
    if (store && liveSessionFile && livePending !== undefined) store.setProgress(liveSessionFile, livePending);
  }
  pi.on("agent_start", (_e: unknown, ctx: any) => {
    liveSessionFile = ctx?.sessionManager?.getSessionFile?.();
  });
  pi.on("message_update", (event: any, ctx: any) => {
    const ev = event?.assistantMessageEvent;
    if (!ev || !/_delta$/.test(String(ev.type))) return;
    if (!liveSessionFile) liveSessionFile = ctx?.sessionManager?.getSessionFile?.();
    livePending = renderPartial(ev.partial ?? event.message);
    if (!liveFlushTimer) liveFlushTimer = setTimeout(flushLive, 250);
  });
  pi.on("agent_settled", () => {
    if (liveFlushTimer) { clearTimeout(liveFlushTimer); flushLive(); }
  });

  pi.on("session_shutdown", () => {
    if (liveFlushTimer) { clearTimeout(liveFlushTimer); flushLive(); }
    if (store && liveSessionFile) store.clearProgress(liveSessionFile);
    store?.close();
    store = undefined;
  });

  // --------------------------------------------------- run event journal

  agents.onRunEvent((raw: unknown) => {
    const event = raw as TraceEvent;
    if (!store || typeof event?.type !== "string") return;
    const db = store;

    if (event.type === "run_created" && event.run) headers.set(event.run.id, event.run);
    const run = localRunFor(event, db);
    if (!run) return;
    if (event.type === "run_created" && event.run) {
      // Keep the expanded flow: resume rebuilds the remainder of it from stored step values.
      if (run.resumes === 0) db.setFlow(run.id, event.run.flow, event.run.display);
    }

    const detail =
      event.type === "node_completed"
        ? (typeof event.value === "string" ? event.value : jsonText(event.value))
        : event.type === "node_failed"
          ? event.error
          : undefined;

    db.appendEvent({
      runId: run.id,
      type: event.type,
      at: event.at,
      summary: summarize(event),
      nodePath: event.path,
      nodeInstance: event.instance,
      nodeKind: event.kind,
      agent: event.profile,
      label: event.label ?? nodeNames.get(`${event.runId ?? ""}:${event.instance ?? event.path ?? ""}`),
      detail: detail ?? (event.type === "node_session" ? event.sessionFile : undefined),
      value: event.type === "node_completed" ? event.value : undefined,
      stepIndex: event.type === "node_completed" ? topLevelStepIndex(event.path, run.resume_offset) : undefined,
    });

    if (event.type === "run_completed") {
      const header = headers.get(event.runId ?? "");
      const status = (event.status ?? "failed") as "completed" | "failed" | "stopped";
      const markdown = presentResult(event.value, header?.display);
      db.markFinished(run.id, {
        status,
        error: event.error,
        resultMarkdown: markdown,
        resultJson: jsonText(event.value),
        agents: event.agents,
        at: event.at,
      });
      if (status === "completed") {
        db.createCheckpoint({
          id: randomUUID(),
          runId: run.id,
          kind: "final_review",
          title: "Attorney review of final report",
          summaryMarkdown: markdown,
        });
      } else {
        db.cancelPendingCheckpoints(run.id, `Workflow ${status}.`);
      }
      headers.delete(event.runId ?? "");
      if (event.runId) piToLocal.delete(event.runId);
    }
  });

  // ------------------------------------------------------- app command

  pi.registerCommand("orchestrator", {
    description:
      "OrchestratorAI control: start|stop|ping <json>. Used by the macOS app over RPC.",
    handler: async (args: string, ctx: any) => {
      const db = openStore(ctx.cwd);
      const [sub, ...rest] = args.trim().split(/\s+/);
      const rawJson = rest.join(" ");
      try {
        switch (sub) {
          case "ping": {
            reply({ ok: true, op: "ping", store: db.path, projectDir });
            return;
          }
          case "start": {
            const input = parseJsonArg(rawJson);
            const workflow = typeof input.workflow === "string" ? input.workflow : "";
            if (!workflow) throw new Error("'workflow' is required");
            const runId = typeof input.runId === "string" && input.runId ? input.runId : randomUUID();
            const title = typeof input.title === "string" && input.title ? input.title : workflow;
            const params = { ...stringMap(input.params), run_id: runId };
            const row = db.createRun({
              id: runId,
              workflow,
              title,
              sourceDocument: typeof input.sourceDocument === "string" ? input.sourceDocument : undefined,
              params,
              model: typeof input.model === "string" ? input.model : ctx.model?.id,
            });
            db.appendEvent({ runId: row.id, type: "queued", summary: `Queued ${workflow}` });
            try {
              const started = await agents.start({ workflow, params, label: title });
              db.markStarted(row.id, started.runId);
              piToLocal.set(started.runId, row.id);
              reply({ ok: true, op: "start", runId: row.id, piRunId: started.runId, warnings: started.warnings ?? [] });
            } catch (error) {
              const message = error instanceof Error ? error.message : String(error);
              db.appendEvent({ runId: row.id, type: "start_failed", summary: `Could not start — ${message}` });
              db.markFinished(row.id, { status: "failed", error: message });
              reply({ ok: false, op: "start", runId: row.id, error: message });
            }
            return;
          }
          case "resume": {
            const input = parseJsonArg(rawJson);
            const runId = typeof input.runId === "string" ? input.runId : "";
            const row = db.getRun(runId);
            if (!row) throw new Error(`unknown run '${runId}'`);
            if (row.status === "completed") throw new Error("run already completed");
            const { flow, resumeAt, resumeOffset, display } = buildResumeFlow(row, db.completedStepValues(row.id), db.stepOverrides(row.id));
            db.appendEvent({ runId: row.id, type: "resume", summary: `Resuming from step ${resumeAt + 1} (${row.resumes + 1}${row.resumes === 0 ? "st" : row.resumes === 1 ? "nd" : "th"} resume)` });
            try {
              const started = await agents.start({ flow, label: `${row.title} (resumed)`, display } as never);
              db.markResumed(row.id, started.runId, resumeOffset);
              piToLocal.set(started.runId, row.id);
              reply({ ok: true, op: "resume", runId: row.id, piRunId: started.runId, resumeAt, warnings: started.warnings ?? [] });
            } catch (error) {
              const message = error instanceof Error ? error.message : String(error);
              db.appendEvent({ runId: row.id, type: "start_failed", summary: `Could not resume — ${message}` });
              reply({ ok: false, op: "resume", runId: row.id, error: message });
            }
            return;
          }
          case "stop": {
            const input = parseJsonArg(rawJson);
            const runId = typeof input.runId === "string" ? input.runId : "";
            const row = db.getRun(runId);
            if (!row?.pi_run_id) throw new Error(`no live run '${runId}'`);
            await agents.stop(row.pi_run_id);
            db.cancelPendingCheckpoints(row.id, "Stopped by the user.");
            reply({ ok: true, op: "stop", runId });
            return;
          }
          default:
            throw new Error("usage: /orchestrator start|resume|stop|ping <json>");
        }
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        reply({ ok: false, op: sub ?? "", error: message });
      }
    },
  });

  // --------------------------------------------------------- HITL gate

  pi.registerTool({
    name: "attorney_review",
    label: "Attorney review",
    description:
      "Pause this workflow until a supervising attorney records a decision in the " +
      "OrchestratorAI console. Call it only when your task explicitly instructs you " +
      "to request an attorney decision. Returns the decision (approved or " +
      "changes_requested) and any attorney comment.",
    parameters: Type.Object({
      run_id: Type.String({
        description: "The OrchestratorAI run id given in your task. Pass an empty string if none was given.",
      }),
      title: Type.String({ description: "Short title of what the attorney is deciding." }),
      summary: Type.String({ description: "Markdown the attorney should read before deciding." }),
    }),
    async execute(_id: string, params: { run_id: string; title: string; summary: string }, signal: AbortSignal | undefined, _onUpdate: unknown, ctx: any) {
      const db = openStore(ctx.cwd);
      const run =
        (params.run_id && (db.getRun(params.run_id) ?? db.findRunByPiId(params.run_id))) ||
        db.latestRunningRun();
      if (!run) {
        return {
          content: [{ type: "text", text: "DECISION: skipped\nCOMMENT: No OrchestratorAI console is attached to this run; continue without an attorney gate." }],
          details: { skipped: true },
        };
      }

      // Idempotent per (run, title): a delegated agent that calls this tool
      // twice for the same decision reuses the existing checkpoint instead of
      // asking the attorney the same question again.
      const existing = db.findCheckpointByTitle(run.id, params.title);
      if (existing && existing.status !== "pending" && existing.status !== "cancelled") {
        const comment = existing.decision_comment?.trim() || "(no comment)";
        return {
          content: [{ type: "text", text: `DECISION: ${existing.status}\nCOMMENT: ${comment}` }],
          details: { checkpointId: existing.id, status: existing.status, reused: true },
        };
      }
      const checkpoint = existing && existing.status === "pending"
        ? existing
        : db.createCheckpoint({
            id: randomUUID(),
            runId: run.id,
            kind: "gate",
            title: params.title,
            summaryMarkdown: params.summary,
          });
      if (!existing || existing.status !== "pending") {
        db.appendEvent({ runId: run.id, type: "gate_requested", summary: `Waiting for attorney — ${params.title}`, detail: params.summary });
      }

      const startedAt = Date.now();
      while (true) {
        if (signal?.aborted) {
          // The agent is going away (Pi killed, run stopped) but the attorney has not decided.
          // Leave the checkpoint pending: a resumed gate step finds it and waits on the same row.
          // An explicit /orchestrator stop cancels pending checkpoints itself.
          db.appendEvent({ runId: run.id, type: "gate_interrupted", summary: `Gate interrupted, still awaiting attorney — ${params.title}` });
          throw new Error("attorney_review interrupted");
        }
        const current = db.getCheckpoint(checkpoint.id);
        if (current && current.status !== "pending") {
          const comment = current.decision_comment?.trim() || "(no comment)";
          db.appendEvent({ runId: run.id, type: "gate_decided", summary: `Attorney ${current.status.replace("_", " ")} — ${params.title}`, detail: comment });
          return {
            content: [{ type: "text", text: `DECISION: ${current.status}\nCOMMENT: ${comment}` }],
            details: { checkpointId: checkpoint.id, status: current.status },
          };
        }
        if (Date.now() - startedAt > GATE_MAX_WAIT_MS) {
          db.cancelPendingCheckpoints(run.id, "Timed out waiting for an attorney decision.");
          return {
            content: [{ type: "text", text: "DECISION: timed_out\nCOMMENT: No attorney decision was recorded in time." }],
            details: { checkpointId: checkpoint.id, status: "timed_out" },
          };
        }
        await sleep(GATE_POLL_MS, signal);
      }
    },
  });

  // ------------------------------------------------------- Jev rubrics

  let jevClient: JevClient | undefined;
  let jevRubrics: Map<string, Rubric> | undefined;
  function jev(): { client: JevClient; rubrics: Map<string, Rubric> } {
    if (!jevRubrics) jevRubrics = loadRubricDir(process.env.JEV_RUBRIC_DIR ?? defaultRubricDir());
    if (!jevClient) jevClient = new JevClient(); // throws a clear error if TYPESAFE_API_KEY is unset
    return { client: jevClient, rubrics: jevRubrics };
  }

  pi.registerTool({
    name: "jev_check",
    label: "Jev rubric check",
    description:
      "Run a named OrchestratorAI rubric (a typed, calibrated decision - not an LLM) against text and get " +
      "a routed decision: pass (safe to use), review (a human should look), or block (do not use this " +
      "content). Rubrics: witness-coaching (does witness-prep text script or re-frame testimony?), " +
      "citation-in-record (is a claim supported by the record? inputs claim+record), severity-normalize " +
      "(HIGH/MEDIUM/LOW for one finding), privilege-coding, signal-classify. Call it only when your task " +
      "tells you to.",
    parameters: Type.Object({
      rubric: Type.String({ description: "Rubric name, e.g. witness-coaching" }),
      inputs: Type.Union([Type.String(), Type.Record(Type.String(), Type.Any())], {
        description: "The text for single-input rubrics, or an object of the rubric's named inputs.",
      }),
      run_id: Type.String({ description: "The OrchestratorAI run id given in your task; empty if none." }),
    }),
    async execute(_id: string, params: { rubric: string; inputs: string | Record<string, unknown>; run_id: string }, _signal: AbortSignal | undefined, _onUpdate: unknown, ctx: any) {
      const db = openStore(ctx.cwd);
      const { client, rubrics } = jev();
      const rubric = rubrics.get(params.rubric);
      if (!rubric) throw new Error(`unknown rubric '${params.rubric}'. Available: ${[...rubrics.keys()].join(", ")}`);
      const result = await runRubric(client, rubric, params.inputs);
      const run = params.run_id ? (db.getRun(params.run_id) ?? db.findRunByPiId(params.run_id)) : undefined;
      const preview = typeof params.inputs === "string" ? params.inputs : JSON.stringify(params.inputs);
      db.recordEvaluation({
        id: randomUUID(), runId: run?.id, rubric: result.rubric, rubricVersion: result.version,
        decision: result.decision, reason: result.reason, answers: result.answers,
        statePreview: preview.slice(0, 400), model: result.model,
        inputTokens: result.usage?.input_tokens, outputTokens: result.usage?.output_tokens,
      });
      if (run) db.appendEvent({ runId: run.id, type: "jev_check", summary: `Jev ${result.rubric} → ${result.decision} (${result.reason})`, detail: JSON.stringify(result.answers, null, 2) });
      return {
        content: [{ type: "text", text: JSON.stringify({ decision: result.decision, reason: result.reason, answers: result.answers }, null, 2) }],
        details: { rubric: result.rubric, version: result.version, decision: result.decision },
      };
    },
  });

  // ------------------------------------------------------ typed run state

  function resolveRun(db: RunStore, runId: string): RunRow {
    const run = (runId && (db.getRun(runId) ?? db.findRunByPiId(runId))) || db.latestRunningRun();
    if (!run) throw new Error("no run to attach state to (pass the run_id from your task)");
    return run;
  }

  pi.registerTool({
    name: "state_update",
    label: "Update run state",
    description:
      "Write to this run's typed state in the store. Reducers are enforced by the store, not by you: " +
      "'set' replaces, 'append' pushes onto an array, 'merge' overlays object keys. Use it to accumulate " +
      "results across loop iterations (e.g. append this round's record) instead of carrying the whole " +
      "history in your own output. Returns the new value and version.",
    parameters: Type.Object({
      run_id: Type.String({ description: "The OrchestratorAI run id given in your task; empty if none." }),
      key: Type.String({ description: "State key, e.g. rounds" }),
      reducer: Type.Union([Type.Literal("set"), Type.Literal("append"), Type.Literal("merge")]),
      value: Type.Any({ description: "The value to set, the item(s) to append, or the object to merge." }),
    }),
    async execute(_id: string, params: { run_id: string; key: string; reducer: "set" | "append" | "merge"; value: unknown }, _s: AbortSignal | undefined, _u: unknown, ctx: any) {
      const db = openStore(ctx.cwd);
      const run = resolveRun(db, params.run_id);
      const result = db.updateState(run.id, params.key, params.reducer, params.value);
      db.appendEvent({ runId: run.id, type: "state", summary: `state ${params.reducer} ${params.key} → v${result.version}` });
      return { content: [{ type: "text", text: JSON.stringify(result) }], details: { key: params.key, version: result.version } };
    },
  });

  pi.registerTool({
    name: "state_get",
    label: "Read run state",
    description: "Read this run's typed state from the store: one key, or all keys when key is omitted.",
    parameters: Type.Object({
      run_id: Type.String({ description: "The OrchestratorAI run id given in your task; empty if none." }),
      key: Type.Optional(Type.String()),
    }),
    async execute(_id: string, params: { run_id: string; key?: string }, _s: AbortSignal | undefined, _u: unknown, ctx: any) {
      const db = openStore(ctx.cwd);
      const run = resolveRun(db, params.run_id);
      return { content: [{ type: "text", text: JSON.stringify(db.getState(run.id, params.key), null, 2) }], details: {} };
    },
  });
}
