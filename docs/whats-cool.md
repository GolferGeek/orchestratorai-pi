# What's cool about this app

Source notes for a demo video. Everything here was built and verified 2026-09-17 → 2026-09-19; the
"receipts" sections point at the commits and store rows that back each claim.

## The pitch in one breath

We rebuilt Orchestrator Legal — fourteen attorney workflows, every one with human-in-the-loop gates — as
a native Mac app on top of an open-source coding agent and fourteen YAML files. Same workflows, same
local models, no framework. Then we hit the wall every local-model team hits, and fixed it with a
different *kind* of model: a typed decision-maker that enforces rules a language model won't. The
judgment layer became a service the whole suite shares over our tailnet. And the last "cloud" piece is
one config value away from coming home when an open System One model exists.

## The story arc (use this as the video's spine)

1. **Further down the stack.** Local = LangGraph + NestJS + Postgres + web. This = Pi + YAML + SQLite +
   SwiftUI. One file per workflow carries the flow *and* its launch UI. The last eight workflows cost
   zero Swift.
2. **The wall.** Deposition prep generated witness coaching. Five rounds of prompt rules failed; the
   newest Qwen obeyed the rules into paralysis. A generative model cannot be trusted to obey a rule about
   its own output.
3. **A different kind of model.** Jev answers *is this true / which / how much* with calibrated
   probabilities. First guarded run: coaching blocked at confidence 1.00, no human needed.
4. **The asset that outlasts the vendor.** Rubrics, thresholds, labeled cases — versioned, tested, 10/10.
   Portable to any model with the same shape.
5. **Shared, not siloed.** The guards are an MCP on the tailnet today; Enterprise/Local/Apple use the
   same five tools.
6. **Bringing it home.** Jev's economics say "small model." When an open one exists it goes on the Spark
   box, `TYPESAFE_BASE_URL` points at it, nothing else changes.

---

## Demo-able moments, in a good order

Timings are on `qwen3.6` via Ollama on this Mac Studio. Pre-bake the long ones; open the app on a
finished run and narrate the journal.

### 1. Fourteen workflows from YAML (30 s)
- **Show:** the sidebar — five practice groups, 14 entries, all Ready. Click Brief Stress Test: the launch
  card has a "Severity bar" dropdown nobody wrote Swift for. Click Legal Research: no file picker, five
  typed fields. Click Due Diligence: a *folder* picker.
- **Say:** "Every one of these is one YAML file. The flow and the UI live together. The app has never
  heard of any of them."
- **Receipt:** `.pi/workflows/*.yaml` — the ` ```orchestrator-launch ` block in each `doc:`.

### 2. Deterministic launch, journaled run (2 min live)
- **Show:** Document Onboarding → "Conflicting NDA versions" → Start. Header goes *Running*; the runs
  column lists it; expand Activity and watch node events land (classifier ∥ completeness → summary).
  ~3 minutes to done.
- **Say:** "The app sent one slash command. No model decided what to run. Every event you see is a row
  in a SQLite file — that file *is* the contract between the app and the runtime."
- **Receipt:** `.pi/extensions/orchestrator/index.ts` (`/orchestrator start`), `data/orchestrator.sqlite`.

### 3. Human in the loop — in the *middle* (pre-baked, or ~12 min live)
- **Show:** Contract Review → Mutual NDA → Start. After Red ∥ Blue → arbitrator, the **Workflow paused**
  card appears with the arbitration. Type a note, click *Approve and continue*. The summary writer's
  output reflects the note.
- **Say:** "That's not a review at the end. The workflow stopped in the middle, waited for counsel, and
  the note steered the next agent."
- **Receipt:** `contract-review.yaml` step `attorney-gate`; `checkpoints` table.

### 4. Human in the loop — inside a loop, every turn (interactive, ~3 min/turn)
- **Show:** Cross-Exam Simulation → Start. The gate card shows *one* question. Answer as the witness. It
  scores you (evasion / consistency / damage) and the next question adapts — dodge, and it confronts you
  with the actual email from the discovery folder.
- **Say:** "Five gates in a loop. The human's answer is the next input. Then a debrief ranks your weakest
  moments."
- **Best on-screen line from a real run:** *"You cannot re-interpret your own written words in front of
  a judge who can read them."*
- **Receipt:** `cross-exam-simulation.yaml`; the debrief in the store (run `cross-exam-simulation-…`).

### 5. A gate that branches the flow (pre-baked)
- **Show:** Legal Research run. At the gate, *Request changes* with "deepen on DTSA preemption" → the
  journal shows `deepening-researcher` ran; a plain *Approve* skips it.
- **Say:** "The decision isn't just approve/reject — it's a switch. The workflow took a different path
  because a human said so."
- **Receipt:** `legal-research.yaml` — `switch on: "{gate}"`.

### 6. The wall, then the guard (the climax — pre-baked)
- **Show:** Deposition Prep run (Predicted cross-exam). Expand the Activity journal: `answer-prep`
  completed, then `Jev witness-coaching → block (supplies a characterisation or script to adopt)`, then
  the report's Limitations: *"Answer preparation was generated and withheld…"*. Expand the blocked text
  in the Guards card: `"Prepared Answer: Yes, that is correct." "Lock this in early." "Be absolute here."`
- **Say:** "Five hard rules in the persona. The model wrote a script anyway. A calibrated classifier read
  it and said 'no' with 100% confidence, and the workflow dropped it — no human needed. That's the whole
  argument for the second kind of model."
- **Receipt:** `evaluations` table; `orchestratorai-jev/rubrics/guards/witness-coaching.yaml` (v5, with
  the v1→v5 reasoning in the comments); `tests/cases/witness-coaching.yaml` 10/10.

### 7. Jev grades the models (pre-baked)
- **Show:** three probe runs, same task, same guard: qwen3.6 → block; qwen3.8 → froze for 37 min and
  never delivered (but noticed the questions misquoted the record); qwen3-coder-next 80B → passed in
  4 min.
- **Say:** "Same rubric, three models, five minutes each. That's how you pick a model per node now — with
  a grade, not a vibe. And `model:` is per node, so the judgment steps can use the big one and the
  fan-out workers the cheap one."
- **Receipt:** `.pi/workflows/prep-probe-*.yaml`; README "Which local model, per node".

### 8. Crash-resume (pre-baked; the terminal demo is the proof)
- **Show:** a stopped Contract Review run. The **Resume from checkpoint** card lists "Step 1 ·
  red-blue-review" with its output. Click *Edit* → change the arbitration → *Resume workflow*. Only the
  gate and the summary writer run.
- **Say:** "We killed the runtime at the gate. The decision stayed pending — a crash can't cancel what
  counsel hasn't decided. Resume re-bound the finished step and ran two agents, not five. And you can
  edit the state first."
- **Receipt:** commit `27910f6`; run `crash-test-…` in the store: `resumes = 1`, `agents = 2`.

### 9. Live text, no polling (live, any run)
- **Show:** while an agent runs, the report card shows what it's writing — including the report it's
  submitting — updating in place.
- **Say:** "The app never polls. It watches the database file. The agent streams its own output into the
  store, and the app joins it to the run."

### 10. The guards are a service (terminal, 30 s)
- **Show:** `claude mcp list` → `jev ✔ Connected`. `curl` the tailnet address with the token → MCP
  handshake; without → 401. `jev_route_request("Is this witness prep note OK? …")` → picks the rubric,
  runs it, returns `block`.
- **Say:** "One MCP, grouped methods, one typed tool per rubric, and a router that picks the rubric for
  you. It's on our tailnet now. Enterprise gets it the same way."
- **Receipt:** `orchestratorai-jev` (GitHub, private); `deploy/com.orchestratorai.jev-mcp.plist`.

---

## Claims, with what backs them

| Claim | Evidence |
|---|---|
| 14/14 workflows, each a single YAML with its UI | sidebar shows 14 Ready; the last 8 ports touched no Swift |
| Every workflow has completed a real run on local models | `runs` table; agent counts: DD 11, Deal Memo 9, Brief 19, Discovery 14, Depo 4–6, Cross-Exam 17, Trial Sim 12, Matters 6×3, Compliance 14, Sentinel 3, Research 10, KB 1 |
| HITL anywhere: mid-sequence, inside loops, sequential (4 in Discovery), branching, conditional | contract-review, cross-exam, discovery-review, legal-research, deposition-prep |
| Deterministic launch, no model chooses the workflow | `/orchestrator start` → pi-agents `start` op |
| The store is the contract | app reads SQLite; extension writes; any front end could consume it |
| Prompt rules can't stop coaching; a classifier can | 5 failed prompt rounds; guard blocked at 1.00 |
| Rubric tuned on labeled cases, versioned | v1→v5, 10/10 live, reasoning in comments |
| Per-node model choice with a grade | prep probes: 3.6 block / 3.8 froze / coder-next pass |
| Crash-resume | killed at gate → resume ran 2 agents, finished |
| Edit state before resume | `step_overrides` + Resume card editor |
| Typed state with reducers | `run_state`, `state_update`/`state_get`, store-enforced |
| Live streaming, no polling | dispatch source on WAL; `run_progress` |
| Guards shared suite-wide | MCP on the tailnet, token-protected, LaunchAgent |

## The LangGraph comparison (say it exactly this way)

*Parity on human-in-the-loop, ahead on authoring and typed gating, parity on crash-resume — with the
same models it already used, plus a second kind of model it never had.*

Where LangGraph still has an edge: typed state is a tool the agent must call rather than a graph-level
reducer; token-level streaming is per-agent, not per-token in the UI. Neither changes the argument.

## Say the quiet parts (they're what make it credible)

- **Not "local only."** The 14 workflows reason locally; the *guard* sends the text being judged to
  Jev's API. For deposition prep that's generated text about a real witness. Say: *local-first for
  reasoning, cloud-assisted for judgment, by choice, for now* — and that the client already takes a
  local base URL when an open System One model exists.
- **The model probes are probes.** Six runs on three Qwens. What's solid is the harness, not a ranking.
- **We cut a feature rather than ship witness coaching**, and the guard is what let us put it back.
  This is the most trustworthy sentence in the video.
- **Timings are real.** Brief Stress Test ~45 min, Discovery ~30, Trial Sim ~25, Due Diligence ~20,
  Contract Review ~12, Onboarding ~3. Pre-bake anything over five minutes.
- **An agent with `read` can read the store.** The DB lives in the project; a roaming model read it once.
  Fine for a prototype; move the store out before anything real.
- **Hallucinated specifics still slip through** (a deal memo invented a review date). Checklists are
  reliable; incidental prose facts need checking — which is exactly what the `compare_citation_in_record`
  guard is for next.

## Numbers worth saying out loud

- 14 workflows, 63 personas, 8 fixture sets — all synthetic and labelled.
- ~25 real runs in the store; 1,000+ journaled node events; every agent's intermediate output kept.
- witness-coaching rubric: 5 versions, 7 labeled cases, 10/10 live; the 80B model's real output is one of
  the cases.
- Jev: 380 input tokens to block the coaching text; ~$42 per *billion* input tokens.
- Crash-resume: 3 agents before the kill, 2 after, 0 re-run.

## Cheat sheet

```sh
# app
./scripts/build-app.sh && open dist/Pi.app          # PI_PROJECT_PATH=<repo> if it can't find .pi
# runtime
pi --approve                                         # TUI; /contract-review fixtures/example-nda.md
sqlite3 data/orchestrator.sqlite 'select title,status,agents from runs order by created_at desc limit 10;'
# guards
cd ../orchestratorai-jev && npm test                 # 10/10 live
claude mcp list                                      # jev ✔ Connected
curl -s -X POST http://gg-macstudio.tail126196.ts.net:8787/mcp -H "Authorization: Bearer $JEV_MCP_TOKEN" ...
```

Fixtures to reach for on camera: `fixtures/onboarding/conflicting-version-nda.md` (fast, visibly
messy), `matters/contract-review/nda/example-mutual-nda.md` (the gate), `fixtures/discovery/`
(privilege edge cases), `fixtures/litigation/motion-to-dismiss.md` (the debate),
`fixtures/dealroom/` (six planted risks).

Where the pieces live: `.pi/workflows` (flow + UI), `.pi/agents` (personas), `.pi/extensions/orchestrator`
(launch, journal, gates, guards, resume, state, live text), `Sources/Pi` (the shell),
`../orchestratorai-jev` (rubrics, MCP, harness, docs mirror).
