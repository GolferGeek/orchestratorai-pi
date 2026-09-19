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
`;

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

  // -------------------------------------------------------------- events

  appendEvent(event: EventInsert): void {
    this.db
      .prepare(
        `INSERT INTO run_events (run_id, at, type, node_path, node_instance, node_kind, agent, label, summary, detail, payload_json)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
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
