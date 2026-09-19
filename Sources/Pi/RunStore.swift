import Foundation
import SQLite3

/// Reader (and attorney-decision writer) for the on-device run store that the
/// Pi extension maintains at `data/orchestrator.sqlite`. Same schema as
/// `.pi/extensions/orchestrator/store.ts`; WAL mode lets both processes hold
/// the file open at once.
struct RunRecord: Identifiable, Hashable {
    let id: String
    let workflow: String
    let title: String
    let sourceDocument: String?
    let params: [String: String]
    let model: String?
    let piRunId: String?
    let status: String          // queued | running | completed | failed | stopped
    let error: String?
    let resultMarkdown: String?
    let agents: Int?
    let resumes: Int
    let createdAt: String
    let startedAt: String?
    let completedAt: String?
    let updatedAt: String

    var isLive: Bool { status == "queued" || status == "running" }
}

struct RunEventRecord: Identifiable, Hashable {
    let id: Int
    let runId: String
    let at: String
    let type: String
    let nodeInstance: String?
    let agent: String?
    let summary: String
    let detail: String?

    var isFailure: Bool {
        type == "node_failed" || type == "start_failed" || (type == "run_completed" && !summary.hasPrefix("Workflow completed"))
    }
}

struct CheckpointRecord: Identifiable, Hashable {
    let id: String
    let runId: String
    let kind: String            // gate | final_review
    let title: String
    let summaryMarkdown: String?
    let status: String          // pending | approved | changes_requested | cancelled
    let decisionComment: String?
    let requestedAt: String
    let decidedAt: String?

    var isPending: Bool { status == "pending" }
    var isGate: Bool { kind == "gate" }
}

/// One calibrated answer from a Jev rubric question, reduced to its headline numbers.
struct EvaluationAnswer: Hashable {
    enum Kind: String, Hashable {
        case noul, score, choice
    }

    let questionId: String
    let kind: Kind
    /// Probability the statement is true (`noul` answers only).
    let noul: Double?
    /// Probability-weighted level (`score` answers only).
    let score: Double?
    /// Selected option (`choice` answers only).
    let choice: String?
    /// Calibrated confidence (`score` and `choice` answers; nouls carry none).
    let confidence: Double?

    /// e.g. `scripts_testimony 0.97`, `level 2.00 @1.00`, `severity HIGH @0.90`.
    var headline: String {
        func two(_ value: Double) -> String { String(format: "%.2f", value) }
        let tail: String
        switch kind {
        case .noul:
            tail = noul.map(two) ?? "?"
        case .score:
            tail = (score.map(two) ?? "?") + (confidence.map { " @" + two($0) } ?? "")
        case .choice:
            tail = (choice ?? "?") + (confidence.map { " @" + two($0) } ?? "")
        }
        return "\(questionId) \(tail)"
    }
}

/// A Jev rubric check recorded against a run (`evaluations` table).
struct EvaluationRecord: Identifiable, Hashable {
    let id: String
    let runId: String?
    let rubric: String
    let rubricVersion: Int
    let decision: String        // pass | review | block
    let reason: String?
    let answers: [EvaluationAnswer]
    let answersJSON: String
    let statePreview: String?
    let model: String?
    let inputTokens: Int?
    let outputTokens: Int?
    let at: String

    var isBlock: Bool { decision == "block" }
    var isReview: Bool { decision == "review" }
}

/// Attorney-facing state derived from the engine status plus checkpoints.
enum ReviewState: Hashable {
    case queued
    case running
    case awaitingGate(CheckpointRecord)
    case awaitingReview
    case approved
    case changesRequested
    case failed
    case stopped

    var label: String {
        switch self {
        case .queued: return "Queued"
        case .running: return "Running"
        case .awaitingGate: return "Awaiting attorney decision"
        case .awaitingReview: return "Awaiting attorney review"
        case .approved: return "Approved"
        case .changesRequested: return "Changes requested"
        case .failed: return "Failed"
        case .stopped: return "Stopped"
        }
    }

    var needsAttention: Bool {
        switch self {
        case .awaitingGate, .awaitingReview, .changesRequested, .failed: return true
        default: return false
        }
    }

    var isLive: Bool {
        switch self {
        case .queued, .running, .awaitingGate: return true
        default: return false
        }
    }
}

final class RunStore {
    private var db: OpaquePointer?
    let path: String

    init?(projectDirectory: URL) {
        let url = projectDirectory.appendingPathComponent("data/orchestrator.sqlite")
        path = url.path
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            return nil
        }
        exec("PRAGMA journal_mode = WAL;")
        exec("PRAGMA busy_timeout = 5000;")
        exec(Self.schema)
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    // Mirrors store.ts so the app can open the file before Pi ever ran.
    private static let schema = """
    CREATE TABLE IF NOT EXISTS runs (
      id TEXT PRIMARY KEY, workflow TEXT NOT NULL, title TEXT NOT NULL, source_document TEXT,
      params_json TEXT NOT NULL, model TEXT, pi_run_id TEXT, status TEXT NOT NULL, error TEXT,
      result_markdown TEXT, result_json TEXT, agents INTEGER, created_at TEXT NOT NULL,
      started_at TEXT, completed_at TEXT, updated_at TEXT NOT NULL,
      flow_json TEXT, display TEXT, resume_offset INTEGER NOT NULL DEFAULT 0, resumes INTEGER NOT NULL DEFAULT 0
    );
    CREATE INDEX IF NOT EXISTS runs_pi_run_id ON runs(pi_run_id);
    CREATE INDEX IF NOT EXISTS runs_created_at ON runs(created_at);
    CREATE TABLE IF NOT EXISTS run_events (
      seq INTEGER PRIMARY KEY AUTOINCREMENT, run_id TEXT NOT NULL, at TEXT NOT NULL, type TEXT NOT NULL,
      node_path TEXT, node_instance TEXT, node_kind TEXT, agent TEXT, label TEXT, summary TEXT NOT NULL,
      detail TEXT, payload_json TEXT, value_json TEXT, step_index INTEGER
    );
    CREATE INDEX IF NOT EXISTS run_events_run ON run_events(run_id, seq);
    CREATE TABLE IF NOT EXISTS checkpoints (
      id TEXT PRIMARY KEY, run_id TEXT NOT NULL, kind TEXT NOT NULL, title TEXT NOT NULL,
      summary_markdown TEXT, status TEXT NOT NULL, decision_comment TEXT, requested_at TEXT NOT NULL,
      decided_at TEXT, node_instance TEXT
    );
    CREATE INDEX IF NOT EXISTS checkpoints_run ON checkpoints(run_id, requested_at);
    CREATE TABLE IF NOT EXISTS evaluations (
      id TEXT PRIMARY KEY, run_id TEXT, rubric TEXT NOT NULL, rubric_version INTEGER NOT NULL,
      decision TEXT NOT NULL, reason TEXT, answers_json TEXT NOT NULL, state_preview TEXT,
      model TEXT, input_tokens INTEGER, output_tokens INTEGER, at TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS evaluations_run ON evaluations(run_id, at);
    CREATE TABLE IF NOT EXISTS run_progress (
      session_file TEXT PRIMARY KEY, text TEXT NOT NULL, updated_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS step_overrides (
      run_id TEXT NOT NULL, step_index INTEGER NOT NULL, value_json TEXT NOT NULL, note TEXT, at TEXT NOT NULL,
      PRIMARY KEY (run_id, step_index)
    );
    """

    // MARK: Reads

    func runs() -> [RunRecord] {
        query("SELECT * FROM runs ORDER BY created_at DESC") { Self.run(from: $0) }
    }

    func run(id: String) -> RunRecord? {
        query("SELECT * FROM runs WHERE id = ?", bind: [id]) { Self.run(from: $0) }.first
    }

    func events(runId: String) -> [RunEventRecord] {
        query("SELECT seq, run_id, at, type, node_instance, agent, summary, detail FROM run_events WHERE run_id = ? ORDER BY seq", bind: [runId]) { stmt in
            RunEventRecord(
                id: Int(sqlite3_column_int64(stmt, 0)),
                runId: Self.text(stmt, 1) ?? "",
                at: Self.text(stmt, 2) ?? "",
                type: Self.text(stmt, 3) ?? "",
                nodeInstance: Self.text(stmt, 4),
                agent: Self.text(stmt, 5),
                summary: Self.text(stmt, 6) ?? "",
                detail: Self.text(stmt, 7)
            )
        }
    }

    func checkpoints(runId: String) -> [CheckpointRecord] {
        query("SELECT * FROM checkpoints WHERE run_id = ? ORDER BY requested_at", bind: [runId]) { Self.checkpoint(from: $0) }
    }

    func pendingCheckpoints() -> [CheckpointRecord] {
        query("SELECT * FROM checkpoints WHERE status = 'pending' ORDER BY requested_at") { Self.checkpoint(from: $0) }
    }

    func evaluations(runId: String) -> [EvaluationRecord] {
        query("SELECT * FROM evaluations WHERE run_id = ? ORDER BY at", bind: [runId]) { Self.evaluation(from: $0) }
    }

    /// Decision counts per run, in one pass over the table.
    func evaluationSummary() -> [String: (block: Int, review: Int, pass: Int)] {
        let rows: [(String, Int, Int, Int)] = query(
            """
            SELECT run_id,
                   SUM(CASE WHEN decision = 'block' THEN 1 ELSE 0 END),
                   SUM(CASE WHEN decision = 'review' THEN 1 ELSE 0 END),
                   SUM(CASE WHEN decision = 'pass' THEN 1 ELSE 0 END)
            FROM evaluations WHERE run_id IS NOT NULL GROUP BY run_id
            """
        ) { stmt in
            guard let runId = Self.text(stmt, 0) else { return nil }
            return (
                runId,
                Int(sqlite3_column_int64(stmt, 1)),
                Int(sqlite3_column_int64(stmt, 2)),
                Int(sqlite3_column_int64(stmt, 3))
            )
        }
        var summary: [String: (block: Int, review: Int, pass: Int)] = [:]
        for (runId, block, review, pass) in rows {
            summary[runId] = (block: block, review: review, pass: pass)
        }
        return summary
    }

    func reviewState(for run: RunRecord, checkpoints: [CheckpointRecord]) -> ReviewState {
        if let gate = checkpoints.last(where: { $0.isGate && $0.isPending }) {
            return .awaitingGate(gate)
        }
        switch run.status {
        case "queued": return .queued
        case "running": return .running
        case "failed": return .failed
        case "stopped": return .stopped
        default: break
        }
        guard let final = checkpoints.last(where: { $0.kind == "final_review" }) else {
            return .awaitingReview
        }
        switch final.status {
        case "approved": return .approved
        case "changes_requested": return .changesRequested
        default: return .awaitingReview
        }
    }

    // MARK: Writes (attorney decisions only — the engine journal belongs to Pi)

    @discardableResult
    func decide(checkpointId: String, status: String, comment: String) -> Bool {
        let now = ISO8601DateFormatter().string(from: Date())
        return execute(
            "UPDATE checkpoints SET status = ?, decision_comment = ?, decided_at = ? WHERE id = ? AND status = 'pending'",
            bind: [status, comment, now, checkpointId]
        )
    }

    /// Lets the attorney re-open a completed report for a fresh decision.
    @discardableResult
    func reopenFinalReview(runId: String) -> Bool {
        let now = ISO8601DateFormatter().string(from: Date())
        return execute(
            "INSERT INTO checkpoints (id, run_id, kind, title, summary_markdown, status, requested_at) VALUES (?, ?, 'final_review', 'Attorney review of final report', NULL, 'pending', ?)",
            bind: [UUID().uuidString.lowercased(), runId, now]
        )
    }

    @discardableResult
    func deleteRun(id: String) -> Bool {
        execute("DELETE FROM run_events WHERE run_id = ?", bind: [id])
            && execute("DELETE FROM checkpoints WHERE run_id = ?", bind: [id])
            && execute("DELETE FROM evaluations WHERE run_id = ?", bind: [id])
            && execute("DELETE FROM runs WHERE id = ?", bind: [id])
    }

    /// Marks a queued/running run as stopped when the Pi process died underneath it.
    /// Pending gates are left pending on purpose: a resume re-runs the gate step and
    /// the idempotent attorney_review tool picks the existing checkpoint back up.
    @discardableResult
    func markOrphaned(runId: String, message: String) -> Bool {
        let now = ISO8601DateFormatter().string(from: Date())
        return execute(
            "UPDATE runs SET status = 'stopped', error = ?, completed_at = ?, updated_at = ? WHERE id = ? AND status IN ('queued','running')",
            bind: [message, now, now, runId]
        )
    }

    // MARK: Live text

    struct LiveText: Identifiable, Hashable {
        let sessionFile: String
        let label: String
        let text: String
        let updatedAt: String
        var id: String { sessionFile }
    }

    /// What each still-running agent of a run is writing right now. Children write
    /// run_progress keyed by their session file; the parent's node_session event carries it.
    func liveText(runId: String) -> [LiveText] {
        query(
            """
            SELECT e.detail, e.label, p.text, p.updated_at
            FROM run_events e JOIN run_progress p ON p.session_file = e.detail
            WHERE e.run_id = ? AND e.type = 'node_session'
              AND NOT EXISTS (SELECT 1 FROM run_events d WHERE d.run_id = e.run_id AND d.node_instance = e.node_instance
                              AND d.type IN ('node_completed','node_failed','node_cancelled') AND d.seq > e.seq)
            ORDER BY p.updated_at DESC
            """,
            bind: [runId]
        ) { stmt in
            LiveText(sessionFile: Self.text(stmt, 0) ?? "", label: Self.text(stmt, 1) ?? "agent", text: Self.text(stmt, 2) ?? "", updatedAt: Self.text(stmt, 3) ?? "")
        }
    }

    // MARK: Resume support

    /// A completed top-level step of a run: what resume will re-bind, and what an attorney may edit first.
    struct StepOutput: Identifiable, Hashable {
        let stepIndex: Int
        let label: String
        let valueText: String
        let isOverridden: Bool
        var id: Int { stepIndex }
    }

    func stepOutputs(runId: String) -> [StepOutput] {
        let overrides = Set(query("SELECT step_index FROM step_overrides WHERE run_id = ?", bind: [runId]) { Int(sqlite3_column_int64($0, 0)) })
        return query(
            "SELECT step_index, label, value_json FROM run_events WHERE run_id = ? AND type = 'node_completed' AND step_index IS NOT NULL ORDER BY seq",
            bind: [runId]
        ) { stmt in
            let index = Int(sqlite3_column_int64(stmt, 0))
            let raw = Self.text(stmt, 2) ?? ""
            // Show strings as themselves, anything else as pretty JSON.
            let shown: String
            if let data = raw.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
                if let str = obj as? String { shown = str }
                else if let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) { shown = String(data: pretty, encoding: .utf8) ?? raw }
                else { shown = raw }
            } else { shown = raw }
            return StepOutput(stepIndex: index, label: Self.text(stmt, 1) ?? "step \(index + 1)", valueText: shown, isOverridden: overrides.contains(index))
        }
        .reduce(into: [Int: StepOutput]()) { $0[$1.stepIndex] = $1 }   // latest completion per step wins
        .values.sorted { $0.stepIndex < $1.stepIndex }
    }

    /// Attorney edit of a completed step's output; resume uses it instead of the stored value.
    @discardableResult
    func setStepOverride(runId: String, stepIndex: Int, text: String, note: String?) -> Bool {
        // Store the edited text as a JSON string so the extension can re-bind it as-is.
        guard let data = try? JSONSerialization.data(withJSONObject: text, options: [.fragmentsAllowed]),
              let json = String(data: data, encoding: .utf8) else { return false }
        let now = ISO8601DateFormatter().string(from: Date())
        return execute(
            "INSERT OR REPLACE INTO step_overrides (run_id, step_index, value_json, note, at) VALUES (?, ?, ?, ?, ?)",
            bind: [runId, String(stepIndex), json, note, now]
        )
    }

    @discardableResult
    func clearStepOverride(runId: String, stepIndex: Int) -> Bool {
        execute("DELETE FROM step_overrides WHERE run_id = ? AND step_index = ?", bind: [runId, String(stepIndex)])
    }

    // MARK: SQLite plumbing

    private func exec(_ sql: String) {
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func execute(_ sql: String, bind: [String?]) -> Bool {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        Self.bind(bind, to: stmt)
        return sqlite3_step(stmt) == SQLITE_DONE
    }

    private func query<T>(_ sql: String, bind: [String?] = [], map: (OpaquePointer) -> T?) -> [T] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        Self.bind(bind, to: stmt)
        var rows: [T] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let stmt, let row = map(stmt) { rows.append(row) }
        }
        return rows
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static func bind(_ values: [String?], to stmt: OpaquePointer?) {
        for (index, value) in values.enumerated() {
            if let value {
                sqlite3_bind_text(stmt, Int32(index + 1), value, -1, transient)
            } else {
                sqlite3_bind_null(stmt, Int32(index + 1))
            }
        }
    }

    private static func text(_ stmt: OpaquePointer, _ column: Int32) -> String? {
        guard let cString = sqlite3_column_text(stmt, column) else { return nil }
        return String(cString: cString)
    }

    private static func column(_ stmt: OpaquePointer, _ name: String) -> Int32? {
        for index in 0..<sqlite3_column_count(stmt) {
            if let cName = sqlite3_column_name(stmt, index), String(cString: cName) == name { return index }
        }
        return nil
    }

    private static func text(_ stmt: OpaquePointer, named name: String) -> String? {
        guard let index = column(stmt, name) else { return nil }
        return text(stmt, index)
    }

    private static func int(_ stmt: OpaquePointer, named name: String) -> Int? {
        guard let index = column(stmt, name), sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        return Int(sqlite3_column_int64(stmt, index))
    }

    private static func run(from stmt: OpaquePointer) -> RunRecord? {
        guard let id = text(stmt, named: "id") else { return nil }
        let paramsJSON = text(stmt, named: "params_json") ?? "{}"
        let params = (try? JSONSerialization.jsonObject(with: Data(paramsJSON.utf8)) as? [String: Any])?
            .compactMapValues { $0 as? String } ?? [:]
        return RunRecord(
            id: id,
            workflow: text(stmt, named: "workflow") ?? "",
            title: text(stmt, named: "title") ?? id,
            sourceDocument: text(stmt, named: "source_document"),
            params: params,
            model: text(stmt, named: "model"),
            piRunId: text(stmt, named: "pi_run_id"),
            status: text(stmt, named: "status") ?? "queued",
            error: text(stmt, named: "error"),
            resultMarkdown: text(stmt, named: "result_markdown"),
            agents: int(stmt, named: "agents"),
            resumes: int(stmt, named: "resumes") ?? 0,
            createdAt: text(stmt, named: "created_at") ?? "",
            startedAt: text(stmt, named: "started_at"),
            completedAt: text(stmt, named: "completed_at"),
            updatedAt: text(stmt, named: "updated_at") ?? ""
        )
    }

    private static func checkpoint(from stmt: OpaquePointer) -> CheckpointRecord? {
        guard let id = text(stmt, named: "id") else { return nil }
        return CheckpointRecord(
            id: id,
            runId: text(stmt, named: "run_id") ?? "",
            kind: text(stmt, named: "kind") ?? "gate",
            title: text(stmt, named: "title") ?? "",
            summaryMarkdown: text(stmt, named: "summary_markdown"),
            status: text(stmt, named: "status") ?? "pending",
            decisionComment: text(stmt, named: "decision_comment"),
            requestedAt: text(stmt, named: "requested_at") ?? "",
            decidedAt: text(stmt, named: "decided_at")
        )
    }

    private static func evaluation(from stmt: OpaquePointer) -> EvaluationRecord? {
        guard let id = text(stmt, named: "id") else { return nil }
        let answersJSON = text(stmt, named: "answers_json") ?? "{}"
        return EvaluationRecord(
            id: id,
            runId: text(stmt, named: "run_id"),
            rubric: text(stmt, named: "rubric") ?? "",
            rubricVersion: int(stmt, named: "rubric_version") ?? 0,
            decision: text(stmt, named: "decision") ?? "review",
            reason: text(stmt, named: "reason"),
            answers: answers(fromJSON: answersJSON),
            answersJSON: answersJSON,
            statePreview: text(stmt, named: "state_preview"),
            model: text(stmt, named: "model"),
            inputTokens: int(stmt, named: "input_tokens"),
            outputTokens: int(stmt, named: "output_tokens"),
            at: text(stmt, named: "at") ?? ""
        )
    }

    /// `{ "<questionId>": { "type": "noul", "noul": 0.97 } | { "type": "score", "score": 2.0, "confidence": 1.0, ... } | { "type": "choice", "choice": "x", "confidence": 0.9, ... } }`
    private static func answers(fromJSON json: String) -> [EvaluationAnswer] {
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { return [] }
        func number(_ value: Any?) -> Double? {
            if let number = value as? NSNumber { return number.doubleValue }
            if let string = value as? String { return Double(string) }
            return nil
        }
        return object.keys.sorted().compactMap { questionId in
            guard let answer = object[questionId] as? [String: Any],
                  let kind = (answer["type"] as? String).flatMap(EvaluationAnswer.Kind.init(rawValue:)) else { return nil }
            return EvaluationAnswer(
                questionId: questionId,
                kind: kind,
                noul: kind == .noul ? number(answer["noul"]) : nil,
                score: kind == .score ? number(answer["score"]) : nil,
                choice: kind == .choice ? answer["choice"] as? String : nil,
                confidence: kind == .noul ? nil : number(answer["confidence"])
            )
        }
    }
}
