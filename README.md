# OrchestratorAI - Pi

A local, Pi-native legal agent workspace.

This project is intentionally not a second web platform. Pi supplies the interactive agent, built-in tools, sessions, model interface, and extension system; [pi-agents](https://github.com/mavam/pi-agents) supplies the workflow algebra. This repository supplies the legal operating context, skills, agent personas, saved workflows, and a thin native macOS shell.

## How the pieces fit

```text
.pi/workflows/*.yaml      the workflow AND its launch UI (one file per offering)
.pi/agents/*.md           agent personas (who), incl. the attorney-gate persona
.pi/skills/               legal skills loaded by personas
knowledge/frameworks/     GDPR / HIPAA / SOX text the compliance evaluators cite
.pi/extensions/orchestrator/
  index.ts                /orchestrator start|stop|ping, run journal, attorney_review + jev_check tools
  store.ts                SQLite schema + writer (node:sqlite, no native deps)
data/orchestrator.sqlite  on-device run store (git-ignored); the app reads it
Sources/Pi/               SwiftUI shell: catalog, launch, journal, HITL checkpoints
```

Three design rules:

1. **Deterministic launch.** The app sends `/orchestrator start {json}` over Pi RPC. Extension slash commands execute immediately with no model round-trip, and the extension calls pi-agents' `start` op with the workflow name and literal params. The root model never decides whether — or which — workflow runs.
2. **The database is the contract.** The extension journals every pi-agents run event (workflow tree, node lifecycle, intermediate values, final result) into `data/orchestrator.sqlite`. The app polls that file; nothing is smuggled through the RPC UI channel. Any other front end (a CLI, a web view, the Apple lab) can consume the same store.
3. **One file per workflow, UI included.** pi-agents rejects unknown top-level keys, so each workflow's launch UI lives in a fenced ` ```orchestrator-launch ` block inside its `doc:`. pi-agents treats it as documentation; the app renders it (file picker label, param fields, demo samples, attorney-review copy). Field defaults come from the workflow's `params`. Drop a new YAML with a launch block into `.pi/workflows/` and it appears in the app with no Swift change.

## Human in the loop

Two checkpoint kinds, both rows in the `checkpoints` table:

- **Gate** (mid-flow). A workflow step uses the `attorney-gate` persona, whose only tool is `attorney_review`. The tool writes a pending checkpoint and blocks until the attorney approves or requests changes in the app; the decision and note are returned to the workflow verbatim and can steer later steps (contract-review feeds them into summary generation). From the Pi TUI, with no console attached, the gate is skipped automatically.
- **Final review** (post-run). Created by the extension when a run completes. The app shows the report and the parsed "Attorney review focus" checklist, and records Approve / Request changes.

## Checkpointing and resume

Every run is resumable from the store, without pi-agents support for it:

- **Crash-resume.** The expanded flow is stored at `run_created` and every top-level step's value at
  `node_completed`. `/orchestrator resume {runId}` rebuilds the remainder as an inline flow — `value`
  nodes re-bind the completed steps (an attorney override wins), then the remaining steps run with params
  substituted — and starts it under the same run id. A step that was mid-way (a loop, a waiting gate)
  re-runs; a gate the attorney already decided is picked straight back up because `attorney_review` is
  idempotent per (run, title), and a crash never cancels a pending decision (only an explicit stop does).
  Verified by killing Pi at the contract-review gate: resume ran two more agent calls, not five.
- **Edit state before resume.** A stopped run's completed steps are listed in the app; an attorney can
  replace a step's output and resume — the remainder sees the edited value.
- **Typed run state with reducers.** `state_update(key, reducer, value)` / `state_get` tools, with `set`,
  `append`, and `merge` enforced by the store rather than by the model, so loops accumulate results in
  the store instead of growing their own context.
- **Live text, no polling.** The app watches the store's WAL with a dispatch source instead of a timer;
  each delegated agent streams what it is writing (including the result it is submitting) into
  `run_progress`, and the app shows it for the running node.

## Requirements

- Pi ≥ 0.85 (`npm i -g @earendil-works/pi-coding-agent`) and Node ≥ 22.5 (`node:sqlite`).
- pi-agents is declared in `.pi/settings.json` (`npm:pi-agents@0.21.0`); Pi installs it on first trusted run.
- Ollama with the model named in the app's "Local model" field (default `qwen3.6:latest`). See [docs/local-models.md](docs/local-models.md).
- Project trust. Delegated agents are spawned without `--approve`, so the project must be trusted persistently: run `pi` here once and `/trust`, or click **Trust this project for Pi** in the app (both write `~/.pi/agent/trust.json`).

## Start Pi (terminal)

```sh
pi --approve
```

Saved workflows register as slash commands: `/contract-review fixtures/example-nda.md`. Progress shows in `/workflows`; the run is journaled into the same SQLite store, so it also appears in the app.

## Demo (macOS app)

1. `./scripts/build-app.sh && open dist/Pi.app` (set `PI_PROJECT_PATH` to this repo if the app cannot find `.pi/settings.json`).
2. If prompted, click **Trust this project for Pi**.
3. **Document Onboarding** → demo sample **Incomplete services draft** → Start → work **Attorney intake focus** → Approve / Request changes.
4. **Contract Review** → demo sample **Mutual NDA** → Our side **Receiving party** → Start. After Red/Blue + arbitration, the **Workflow paused** card appears: read the arbitration, add direction, **Approve and continue** (or request changes). The summary step receives your note. Then work **Attorney review focus** and record the final decision.

The Activity disclosure shows the journal: each node's start/finish, the model used, and the intermediate output of every agent (expand a row).

## Legal workflow catalog

All fourteen Legal workflows are Ready: each has a `.pi/workflows/{id}.yaml` carrying both its flow and its
launch UI. Every one below has completed at least one full run on `qwen3.6` through Ollama.

| Workflow | Input | Composition | Attorney gates |
|---|---|---|---|
| `document-onboarding` | document | classifier ∥ completeness → summary | final review |
| `contract-review` | contract | red ∥ blue → arbitrator → **gate** → summary | mid-flow + final |
| `due-diligence` | folder | inventory → map(analyst) → **gate 1** → synthesis → **gate 2** → report | 2 + final |
| `deal-memo` | diligence record | intake → 5 section drafters ∥ → assembly → **gate** → finalize | 1 + final |
| `adversarial-brief` | brief | analyst → round 1 {blue ×3 ∥ → red ×3 ∥ → judge} → switch(converged? skip : round 2) → synthesis → **gate** → fortify → report | 1 + final |
| `discovery-review` | folder | inventory → map(coder) → batcher → **privilege** → **relevance** → **hot docs** → **QA sample** → production set + privilege log | 4 + final |
| `deposition-prep` | typed | case analyst → switch(mode) { outline: questions → research \| cross-exam: opposing counsel → predicted cross } → report | final review |
| `cross-exam-simulation` | typed | strategist → loop(≤5) { question → **gate: you answer as the witness** → scorer } → debrief | one per turn + final |
| `monte-carlo-trial-simulator` | case record | parameter designer → map(sim) { plaintiff ∥ defence → jury } → statistics → report | final review |
| `persistent-case-team` | folder | inventory → entities ∥ timeline ∥ index → record writer (rewrites the matter file) → update report | final review |
| `compliance-audit` | policy | classifier → map(section) vs `knowledge/frameworks` → scorer → **gate** → report | 1 + final |
| `sentinel` | folder | classifier (classify + dedupe) → evaluator vs portfolio → digest | final review |
| `legal-research` | typed | analyst → map(sub-questions) → memo → **gate** → switch(deepen) → report | 1 + final |
| `kb-query` | typed | single cited answer from the knowledge folder | final review |

Ports follow orchestratorai-local's `legal/workflows/*` briefs and its agent-catalog prompts, rewritten
text-first for local models.

**One step is guarded by a classifier, not a prompt.** Local's deposition-prep includes an answer-coaching
node. Five attempts at constraining it with prompt rules each produced text telling the witness how to
re-frame adverse documents — the local model ignores rules about its own output. The step now runs behind
`jev_check` (the `witness-coaching` rubric from the sibling **orchestratorai-jev** repo): the workflow
switches on the calibrated decision — `pass` ships it, `review` shows it to counsel at a gate, `block`
omits it and the report says why. In the first guarded run Jev blocked it at confidence 1.00. Every
evaluation is recorded in the store's `evaluations` table. See [docs/jev.md](docs/jev.md).

Two workflows are honest adaptations rather than literal ports, and say so in their `doc:` block: **persistent-case-team** keeps matter state in a Markdown record each run reads and rewrites
(Local uses Postgres), and **sentinel** screens a folder of signal files rather than polling the network.

The launch block's `file:` takes `kind: file` (the default), `kind: folder`, or `kind: none` for
workflows driven entirely by typed fields.

**Which local model, per node.** `model:` is a per-node option, so judgment-heavy single steps and
fan-out workers can differ. On the witness-preparation probe (same task, same guard): qwen3.6 scripted
testimony every time; qwen3.8 obeyed the rules into paralysis and never delivered; **qwen3-coder-next
(80B)** followed the format, quoted the record, and passed the guard in four minutes - despite the name,
it is the newest and largest model on the machine. `.pi/workflows/prep-probe-*.yaml` are the probes;
the models must be registered in `~/.pi/agent/models.json` for an explicit `model:` to validate.

**Local-model rule of thumb:** pi-agents requires every agent to finish by calling
`pi_agents_submit_result`; local models drop that when the prompt gets very large. Keep each node's
context bounded (no accumulating records across loop iterations — unroll instead), put the delivery
instruction as the *last* line of every task, and use `onError: collect` on parallel teams so one lapse
does not sink a run.

### Fixtures

`fixtures/dealroom` (5-document deal room), `fixtures/discovery` (6-document corpus with real privilege
edge cases), `fixtures/litigation` (a motion to dismiss and a structured case record),
`fixtures/compliance`, `fixtures/onboarding`, `fixtures/sentinel/signals`, plus
`fixtures/dealroom-diligence-record.md`. All synthetic and labelled as such.

## Store schema

`runs` (one per launch; engine status, params, final Markdown/JSON) · `run_events` (journal) · `checkpoints` (gate / final_review with attorney decision) · `evaluations` (every Jev rubric decision, with answers and confidence). The Swift reader and the TypeScript writer share the schema; see `.pi/extensions/orchestrator/store.ts`.
