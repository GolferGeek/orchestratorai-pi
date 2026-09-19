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
  index.ts                /orchestrator start|stop|ping, run journal, attorney_review tool
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

A gate keeps the Pi process (and the waiting agent) alive, so it lives as long as the app session. Final review does not need Pi running.

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

The sidebar lists Legal's 14-workflow catalog grouped as in the product registry. **Ready** entries have `.pi/workflows/{id}.yaml` with a launch block; **Coming soon** entries are listed honestly with Start disabled.

| Workflow | Input | Composition | Gate |
|---|---|---|---|
| `document-onboarding` | document | classifier ∥ completeness → summary | final review |
| `contract-review` | contract | red ∥ blue → arbitrator → **gate** → summary | mid-flow + final |
| `adversarial-brief` | brief | analyst → round 1 {blue ×3 ∥ → red ×3 ∥ → judge} → switch(converged? skip : round 2) → synth → **gate** → fortify → report | mid-flow + final |
| `legal-research` | typed question | analyst → map(sub-questions) → memo → **gate** → switch(deepen) → report | mid-flow + final |
| `kb-query` | typed question | single cited answer from the knowledge folder | final review |
| `compliance-audit` | policy document | classifier → map(sections) evaluator vs `knowledge/frameworks` → scorer → **gate** → report | mid-flow + final |

Ports follow orchestratorai-local's `legal/workflows/*` briefs and the agent-catalog prompts, rewritten text-first for local models. All six have completed full runs on `qwen3.6` via Ollama.

**Local-model rule of thumb:** pi-agents requires every agent to finish by calling `pi_agents_submit_result`; local models drop that when the prompt gets very large. Keep each node's context bounded (no accumulating records across loop iterations — unroll instead), put the delivery instruction as the *last* line of every task, and use `onError: collect` on parallel teams so one lapse doesn't sink a run. The launch block's `file:` takes `kind: file` (default), `kind: folder`, or `kind: none` (typed fields only).

Remaining (Coming soon): due-diligence, deal-memo, discovery-review, deposition-prep, cross-exam-simulation, monte-carlo-trial-simulator, persistent-case-team, sentinel. The folder-input ones need `kind: folder` plus a map over an inventory; cross-exam is a loop of `attorney_review` gates (one per question).

## Store schema

`runs` (one per launch; engine status, params, final Markdown/JSON) · `run_events` (journal) · `checkpoints` (gate / final_review with attorney decision). The Swift reader and the TypeScript writer share the schema; see `.pi/extensions/orchestrator/store.ts`.
