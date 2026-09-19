/**
 * On-device run store shared by the Pi extension (writer) and the macOS app
 * (reader + attorney decisions). One SQLite file under the project's data/
 * directory, WAL mode so both processes can hold it open at once.
 *
 * Node ≥ 22.5 ships `node:sqlite`; Pi 0.85 runs on Node 26, so no native
 * dependency is needed on the extension side. The Swift app reads the same
 * file through the system SQLite3 library.
 */

import * as fs from "node:fs";
import * as path from "node:path";
import { DatabaseSync } from "node:sqlite";

export const STORE_RELATIVE_PATH = "data/orchestrator.sqlite";

export type RunStatus =
  | "queued"
  | "running"
  | "completed"
  | "failed"
  | "stopped";

export type CheckpointKind = "gate" | "final_review";
export type CheckpointStatus =
  | "pending"
  | "approved"
  | "changes_requested"
  | "cancelled";

export interface RunRow {
  id: string;
  workflow: string;
  title: string;
  source_document: string | null;
  params_json: string;
  model: string | null;
  pi_run_id: string | null;
  status: RunStatus;
  error: string | null;
  result_markdown: string | null;
  result_json: string | null;
  agents: number | null;
  flow_json: string | null;
  display: string | null;
  resume_offset: number;
  resumes: number;
  created_at: string;
  started_at: string | null;
  completed_at: string | null;
  updated_at: string;
}

export interface CheckpointRow {
  id: string;
  run_id: string;
  kind: CheckpointKind;
  title: string;
  summary_markdown: string | null;
  status: CheckpointStatus;
  decision_comment: string | null;
  requested_at: string;
  decided_at: string | null;
  node_instance: string | null;
}

export interface EventInsert {
  runId: string;
  type: string;
  summary: string;
  nodePath?: string;
  nodeInstance?: string;
  nodeKind?: string;
  agent?: string;
  label?: string;
  detail?: string;
  payload?: unknown;
  at?: number;
  /** Raw JSON of a completed node's value, kept for resume. */
  value?: unknown;
  /** Index of the top-level sequence step this event belongs to, if any. */
  stepIndex?: number;
}

const SCHEMA = `
CREATE TABLE IF NOT EXISTS runs (
  id TEXT PRIMARY KEY,
  workflow TEXT NOT NULL,
  title TEXT NOT NULL,
  source_document TEXT,
  params_json TEXT NOT NULL,
  model TEXT,
  pi_run_id TEXT,
  status TEXT NOT NULL,
  error TEXT,
  result_markdown TEXT,
  result_json TEXT,
  agents INTEGER,
  created_at TEXT NOT NULL,
  started_at TEXT,
  completed_at TEXT,
  updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS runs_pi_run_id ON runs(pi_run_id);
CREATE INDEX IF NOT EXISTS runs_created_at ON runs(created_at);

CREATE TABLE IF NOT EXISTS run_events (
  seq INTEGER PRIMARY KEY AUTOINCREMENT,
  run_id TEXT NOT NULL,
  at TEXT NOT NULL,
  type TEXT NOT NULL,
  node_path TEXT,
  node_instance TEXT,
  node_kind TEXT,
  agent TEXT,
  label TEXT,
  summary TEXT NOT NULL,
  detail TEXT,
  payload_json TEXT
);
CREATE INDEX IF NOT EXISTS run_events_run ON run_events(run_id, seq);

CREATE TABLE IF NOT EXISTS checkpoints (
  id TEXT PRIMARY KEY,
  run_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  title TEXT NOT NULL,
  summary_markdown TEXT,
  status TEXT NOT NULL,
  decision_comment TEXT,
  requested_at TEXT NOT NULL,
  decided_at TEXT,
  node_instance TEXT
);
CREATE INDEX IF NOT EXISTS checkpoints_run ON checkpoints(run_id, requested_at);

CREATE TABLE IF NOT EXISTS evaluations (
  id TEXT PRIMARY KEY,
  run_id TEXT,
  rubric TEXT NOT NULL,
  rubric_version INTEGER NOT NULL,
  decision TEXT NOT NULL,
  reason TEXT,
  answers_json TEXT NOT NULL,
  state_preview TEXT,
  model TEXT,
  input_tokens INTEGER,
  output_tokens INTEGER,
  at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS evaluations_run ON evaluations(run_id, at);

CREATE TABLE IF NOT EXISTS run_progress (
  session_file TEXT PRIMARY KEY,   -- joins run_events.detail of the node_session event
  text TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS run_state (
  run_id TEXT NOT NULL,
  key TEXT NOT NULL,
  value_json TEXT NOT NULL,
  reducer TEXT NOT NULL,          -- set | append | merge
  version INTEGER NOT NULL DEFAULT 1,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (run_id, key)
);

CREATE TABLE IF NOT EXISTS step_overrides (
  run_id TEXT NOT NULL,
  step_index INTEGER NOT NULL,
  value_json TEXT NOT NULL,
  note TEXT,
  at TEXT NOT NULL,
  PRIMARY KEY (run_id, step_index)
);
`;

/** Columns added after the first release; applied idempotently at open. */
const MIGRATIONS: Array<{ table: string; column: string; ddl: string }> = [
  { table: "runs", column: "flow_json", ddl: "ALTER TABLE runs ADD COLUMN flow_json TEXT" },
  { table: "runs", column: "display", ddl: "ALTER TABLE runs ADD COLUMN display TEXT" },
  { table: "runs", column: "resume_offset", ddl: "ALTER TABLE runs ADD COLUMN resume_offset INTEGER NOT NULL DEFAULT 0" },
  { table: "runs", column: "resumes", ddl: "ALTER TABLE runs ADD COLUMN resumes INTEGER NOT NULL DEFAULT 0" },
  { table: "run_events", column: "value_json", ddl: "ALTER TABLE run_events ADD COLUMN value_json TEXT" },
  { table: "run_events", column: "step_index", ddl: "ALTER TABLE run_events ADD COLUMN step_index INTEGER" },
];

function nowIso(at?: number): string {
  return new Date(at ?? Date.now()).toISOString();
}

function textOf(value: unknown): string | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value === "string") return value;
  try {
    return JSON.stringify(value, null, 2);
  } catch {
    return String(value);
  }
}

export class RunStore {
  readonly path: string;
  private db: DatabaseSync;

  constructor(projectDir: string) {
    this.path = path.join(projectDir, STORE_RELATIVE_PATH);
    fs.mkdirSync(path.dirname(this.path), { recursive: true });
    this.db = new DatabaseSync(this.path);
    this.db.exec("PRAGMA journal_mode = WAL;");
    this.db.exec("PRAGMA busy_timeout = 5000;");
    this.db.exec("PRAGMA synchronous = NORMAL;");
    this.db.exec(SCHEMA);
    for (const m of MIGRATIONS) {
      const cols = this.db.prepare(`PRAGMA table_info(${m.table})`).all() as Array<{ name: string }>;
      if (!cols.some((c) => c.name === m.column)) this.db.exec(m.ddl);
    }
  }

  close(): void {
    this.db.close();
  }

  // ---------------------------------------------------------------- runs

  createRun(input: {
    id: string;
    workflow: string;
    title: string;
    sourceDocument?: string;
    params: Record<string, string>;
    model?: string;
  }): RunRow {
    const at = nowIso();
    this.db
      .prepare(
        `INSERT INTO runs (id, workflow, title, source_document, params_json, model, status, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, 'queued', ?, ?)`,
      )
      .run(
        input.id,
        input.workflow,
        input.title,
        input.sourceDocument ?? null,
        JSON.stringify(input.params),
        input.model ?? null,
        at,
        at,
      );
    return this.getRun(input.id)!;
  }

  getRun(id: string): RunRow | undefined {
    return this.db.prepare("SELECT * FROM runs WHERE id = ?").get(id) as
      | RunRow
      | undefined;
  }

  findRunByPiId(piRunId: string): RunRow | undefined {
    return this.db
      .prepare("SELECT * FROM runs WHERE pi_run_id = ?")
      .get(piRunId) as RunRow | undefined;
  }

  latestRunningRun(): RunRow | undefined {
    return this.db
      .prepare(
        "SELECT * FROM runs WHERE status IN ('queued','running') ORDER BY created_at DESC LIMIT 1",
      )
      .get() as RunRow | undefined;
  }

  markStarted(id: string, piRunId: string): void {
    const at = nowIso();
    this.db
      .prepare(
        "UPDATE runs SET pi_run_id = ?, status = 'running', started_at = COALESCE(started_at, ?), updated_at = ? WHERE id = ?",
      )
      .run(piRunId, at, at, id);
  }

  markFinished(
    id: string,
    input: {
      status: Exclude<RunStatus, "queued" | "running">;
      error?: string;
      resultMarkdown?: string;
      resultJson?: string;
      agents?: number;
      at?: number;
    },
  ): void {
    const at = nowIso(input.at);
    this.db
      .prepare(
        `UPDATE runs SET status = ?, error = ?, result_markdown = ?, result_json = ?, agents = ?,
           completed_at = ?, updated_at = ? WHERE id = ?`,
      )
      .run(
        input.status,
        input.error ?? null,
        input.resultMarkdown ?? null,
        input.resultJson ?? null,
        input.agents ?? null,
        at,
        at,
        id,
      );
  }

  /** Persist the expanded flow and display path so the run can be resumed later. */
  setFlow(id: string, flow: unknown, display: string | undefined): void {
    this.db
      .prepare("UPDATE runs SET flow_json = ?, display = ?, updated_at = ? WHERE id = ?")
      .run(JSON.stringify(flow), display ?? null, nowIso(), id);
  }

  /** Values of completed top-level steps, by original step index (latest wins). */
  completedStepValues(runId: string): Map<number, unknown> {
    const rows = this.db
      .prepare("SELECT step_index, value_json FROM run_events WHERE run_id = ? AND type = 'node_completed' AND step_index IS NOT NULL ORDER BY seq")
      .all(runId) as Array<{ step_index: number; value_json: string | null }>;
    const out = new Map<number, unknown>();
    for (const r of rows) out.set(r.step_index, r.value_json === null ? null : JSON.parse(r.value_json));
    return out;
  }

  stepOverrides(runId: string): Map<number, unknown> {
    const rows = this.db
      .prepare("SELECT step_index, value_json FROM step_overrides WHERE run_id = ?")
      .all(runId) as Array<{ step_index: number; value_json: string }>;
    return new Map(rows.map((r) => [r.step_index, JSON.parse(r.value_json)]));
  }

  markResumed(id: string, piRunId: string, resumeOffset: number): void {
    const at = nowIso();
    this.db
      .prepare(
        "UPDATE runs SET pi_run_id = ?, status = 'running', error = NULL, completed_at = NULL, resume_offset = ?, resumes = resumes + 1, updated_at = ? WHERE id = ?",
      )
      .run(piRunId, resumeOffset, at, id);
  }

  // ------------------------------------------------------------- progress

  /** Live text of a delegated agent, written by the child process itself. */
  setProgress(sessionFile: string, text: string): void {
    this.db
      .prepare(
        `INSERT INTO run_progress (session_file, text, updated_at) VALUES (?, ?, ?)
         ON CONFLICT(session_file) DO UPDATE SET text = excluded.text, updated_at = excluded.updated_at`,
      )
      .run(sessionFile, text, nowIso());
  }

  clearProgress(sessionFile: string): void {
    this.db.prepare("DELETE FROM run_progress WHERE session_file = ?").run(sessionFile);
  }

  // ---------------------------------------------------------------- state

  /**
   * Typed run state with reducers, enforced here rather than by the model:
   *   set    - replace the value
   *   append - value must be an array; incoming items are pushed (an object is pushed as one item)
   *   merge  - value must be an object; incoming keys overwrite existing ones
   * The reducer is fixed on first write for a key; later writes must agree.
   */
  updateState(runId: string, key: string, reducer: "set" | "append" | "merge", incoming: unknown): { value: unknown; version: number } {
    const row = this.db
      .prepare("SELECT value_json, reducer, version FROM run_state WHERE run_id = ? AND key = ?")
      .get(runId, key) as { value_json: string; reducer: string; version: number } | undefined;
    if (row && row.reducer !== reducer) throw new Error(`state key '${key}' uses reducer '${row.reducer}', not '${reducer}'`);
    let next: unknown;
    const current = row ? JSON.parse(row.value_json) : undefined;
    switch (reducer) {
      case "set": next = incoming; break;
      case "append": {
        const base = Array.isArray(current) ? current : [];
        next = base.concat(Array.isArray(incoming) ? incoming : [incoming]);
        break;
      }
      case "merge": {
        if (incoming === null || typeof incoming !== "object" || Array.isArray(incoming)) throw new Error(`merge into '${key}' needs an object`);
        next = { ...(current && typeof current === "object" && !Array.isArray(current) ? current : {}), ...(incoming as object) };
        break;
      }
    }
    const version = (row?.version ?? 0) + 1;
    this.db
      .prepare(
        `INSERT INTO run_state (run_id, key, value_json, reducer, version, updated_at) VALUES (?, ?, ?, ?, ?, ?)
         ON CONFLICT(run_id, key) DO UPDATE SET value_json = excluded.value_json, version = excluded.version, updated_at = excluded.updated_at`,
      )
      .run(runId, key, JSON.stringify(next), reducer, version, nowIso());
    return { value: next, version };
  }

  getState(runId: string, key?: string): Record<string, unknown> {
    const rows = (key
      ? this.db.prepare("SELECT key, value_json FROM run_state WHERE run_id = ? AND key = ?").all(runId, key)
      : this.db.prepare("SELECT key, value_json FROM run_state WHERE run_id = ?").all(runId)) as Array<{ key: string; value_json: string }>;
    return Object.fromEntries(rows.map((r) => [r.key, JSON.parse(r.value_json)]));
  }

  // -------------------------------------------------------------- events

  appendEvent(event: EventInsert): void {
    this.db
      .prepare(
        `INSERT INTO run_events (run_id, at, type, node_path, node_instance, node_kind, agent, label, summary, detail, payload_json, value_json, step_index)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      )
      .run(
        event.runId,
        nowIso(event.at),
        event.type,
        event.nodePath ?? null,
        event.nodeInstance ?? null,
        event.nodeKind ?? null,
        event.agent ?? null,
        event.label ?? null,
        event.summary,
        event.detail ?? null,
        event.payload === undefined ? null : (textOf(event.payload) ?? null),
        event.value === undefined ? null : JSON.stringify(event.value),
        event.stepIndex ?? null,
      );
  }

  // --------------------------------------------------------- checkpoints

  createCheckpoint(input: {
    id: string;
    runId: string;
    kind: CheckpointKind;
    title: string;
    summaryMarkdown?: string;
    nodeInstance?: string;
  }): CheckpointRow {
    this.db
      .prepare(
        `INSERT INTO checkpoints (id, run_id, kind, title, summary_markdown, status, requested_at, node_instance)
         VALUES (?, ?, ?, ?, ?, 'pending', ?, ?)`,
      )
      .run(
        input.id,
        input.runId,
        input.kind,
        input.title,
        input.summaryMarkdown ?? null,
        nowIso(),
        input.nodeInstance ?? null,
      );
    return this.getCheckpoint(input.id)!;
  }

  getCheckpoint(id: string): CheckpointRow | undefined {
    return this.db
      .prepare("SELECT * FROM checkpoints WHERE id = ?")
      .get(id) as CheckpointRow | undefined;
  }

  /** Most recent checkpoint for this run with the same title, if any. Used to
   * make the attorney_review tool idempotent: an agent that calls it twice for
   * the same decision must not ask the attorney the same question twice. */
  findCheckpointByTitle(runId: string, title: string): CheckpointRow | undefined {
    return this.db
      .prepare(
        "SELECT * FROM checkpoints WHERE run_id = ? AND title = ? ORDER BY requested_at DESC LIMIT 1",
      )
      .get(runId, title) as CheckpointRow | undefined;
  }

  // ---------------------------------------------------------- evaluations

  /** A Jev rubric result, recorded so the app can badge runs and the harness can grade history. */
  recordEvaluation(input: {
    id: string;
    runId?: string;
    rubric: string;
    rubricVersion: number;
    decision: string;
    reason?: string;
    answers: unknown;
    statePreview?: string;
    model?: string;
    inputTokens?: number;
    outputTokens?: number;
  }): void {
    this.db
      .prepare(
        `INSERT INTO evaluations (id, run_id, rubric, rubric_version, decision, reason, answers_json, state_preview, model, input_tokens, output_tokens, at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      )
      .run(
        input.id, input.runId ?? null, input.rubric, input.rubricVersion, input.decision, input.reason ?? null,
        JSON.stringify(input.answers), input.statePreview ?? null, input.model ?? null,
        input.inputTokens ?? null, input.outputTokens ?? null, nowIso(),
      );
  }

  cancelPendingCheckpoints(runId: string, reason: string): void {
    const at = nowIso();
    this.db
      .prepare(
        `UPDATE checkpoints SET status = 'cancelled', decision_comment = ?, decided_at = ?
         WHERE run_id = ? AND status = 'pending'`,
      )
      .run(reason, at, runId);
  }
}
