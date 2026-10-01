# Productizing Pi

A plan, not a build. It covers how the Mac app could be packaged and distributed,
where Pi sits in the OrchestratorAI offering, and draft public wording. Nothing
here has been shipped, and nothing here should be read as a commitment.

Written 2026-09-28, alongside the click-through record in
[verification/2026-09-28-clickthrough.md](verification/2026-09-28-clickthrough.md).

The work this plan describes is tracked as an effort, with the parts it does not
cover (wrapping Pi so there is no command line, a writable project home, an
admin workflow builder, front ends on top):
`~/projects/orchestratorai/efforts/future/pi-mac-app-and-workflow-builder.md`.

## The catalog gate

**Lifted, for what it was gating.** The brief made the Apple catalog gate
conditional on a clean click-through: every screen and all fourteen Legal
workflows launching and either finishing or stopping cleanly at their
human-review gate, on the built app. That is now on the record — all fourteen
pass, driven by real clicks, in
[verification/2026-09-28-clickthrough.md](verification/2026-09-28-clickthrough.md).

Five defects were found and fixed to get there, four of them in the app: a run
orphaned at a gate could never be resumed; the Resume button killed the Pi
process it had just launched; a dying Pi could orphan the run that replaced it;
typed workflows generated run names nothing could display; and `legal-research`
failed at its last step on the local model. All are committed on
`portfolio/legal-catalog-phase2`, and the pass was re-run on the final build.

Two things the gate does **not** cover, and which no one should read it as
covering:

- It says the workflows run. It says nothing about whether their output is any
  good — no report was read for legal quality.
- It says nothing about packaging. Everything in "What exists today" below is
  still true: the app is unsigned, un-notarized, and useless without the
  repository beside it. The hardened-runtime question in option 2 was the first
  thing to be spiked, and it has been — see the result line under option 2.

No Apple catalog work was started, per the brief.

## What exists today, stated plainly

`dist/Pi.app` is a SwiftUI shell around this repository. It is not a standalone
application, and the distance between the two is most of the work below.

| | Today |
|---|---|
| Build | `./scripts/build-app.sh` — `swift build -c release`, then a hand-assembled bundle |
| Signing | None. Ad-hoc, unsigned, un-notarized; Gatekeeper will refuse it on any machine it was not built on |
| Bundle | `CFBundleShortVersionString` 0.1.0, build 1, no icon, `LSMinimumSystemVersion` 13.0 |
| Where the content lives | Outside the app. The shell locates `.pi/settings.json` via `PI_PROJECT_PATH`, the working directory, or two levels up from the bundle — i.e. it expects to sit in `dist/` inside a checkout |
| Runtime dependencies | The `pi` CLI on PATH (npm global), Node ≥ 22.5 for `node:sqlite`, pi-agents `0.21.0` fetched on first trusted run, Ollama serving the chosen model |
| Trust | The project must be trusted persistently (`~/.pi/agent/trust.json`), because delegated agents are spawned without `--approve` |
| Data | `data/orchestrator.sqlite` on the device. The app only reads it; the Pi extension writes it |
| Network | Local by default. The `jev_check` guard is the exception — it calls a hosted TypeSafe endpoint with `TYPESAFE_API_KEY` from the project's `.env` |
| Hardware | The models that behaved on the witness-preparation probe are large (qwen3-coder-next, 80B). This is a workstation-class requirement, not a laptop one |

So a person who is handed `Pi.app` today gets nothing. A person handed the
repository, a working `pi`, Node 22.5, Ollama, and the right model gets the
thing in the demo. Every packaging option below is a way of shortening that
second sentence.

## Packaging options

Roughly in order of effort. They are not exclusive — 1 is the floor, 2 is the
first one a stranger could use, 3 and 4 are how it would be kept current.

### 1. Repository plus build script (what we have)

Ship the git repository. The reader builds the app.

- **For:** zero new work; the project resources are obviously editable, which is
  the point of the design — a new `.pi/workflows/*.yaml` appears in the app with
  no Swift change.
- **Against:** requires Xcode command-line tools, a Swift toolchain, npm, Node
  and Ollama before anything runs. This is a developer artifact.
- **Fits:** internal use, a design partner with an engineer, an open-source
  reference implementation.

### 2. Signed, notarized `.dmg` with the project embedded

Move `.pi/`, `knowledge/`, `fixtures/` and `matters/` into
`Contents/Resources/`, copy them to `~/Library/Application Support/OrchestratorAI/Pi/`
on first launch (so they stay editable and survive an upgrade), sign with a
Developer ID, notarize, staple, and ship a `.dmg`.

- **Work:** an Apple Developer account and Developer ID certificate; a hardened
  runtime; a signing and notarization step in the build script; a first-run
  seed-and-migrate path; an app icon; a real version scheme.
- **Answered — the child processes.** A scratch copy of `dist/Pi.app` signed
  `--options runtime` **with no entitlements at all** ran `kb-query` end to end,
  spawning `pi` and its delegated `pi` child. The hardened runtime is not
  inherited across `exec`, so neither
  `com.apple.security.cs.allow-unsigned-executable-memory` nor
  `disable-library-validation` is needed, and neither should be added. What does
  break the design is the **App Sandbox** — a different entitlement, required
  only for the Mac App Store, which is not on this list. Full record and the
  parts still untested (Gatekeeper, notarization, TCC) in
  [verification/2026-09-30-hardened-runtime-spike.md](verification/2026-09-30-hardened-runtime-spike.md).
- **Still required of the user:** `pi`, Node, Ollama, a model pull. The app can
  detect and explain each, but it cannot supply them.

### 3. Homebrew cask

`brew install --cask orchestratorai-pi`, with `depends_on formula: "node"` and a
caveat naming Ollama and the model. Needs (2) first — a cask of an unsigned app
is a worse experience, not a better one.

- **For:** the audience that would run this already has Homebrew; upgrades are free.
- **Against:** a cask in our own tap has no discovery; homebrew-core would not
  take it while it depends on a globally-installed npm CLI.

### 4. Bundled first-run setup

A first-launch screen that checks for `pi`, Node ≥ 22.5, Ollama and the model,
and offers to install or pull each one, replacing the four manual steps in the
README with a checklist that says what is missing.

- This is the difference between "a demo you run for someone" and "a thing
  someone installs". It is also where the honest failure modes live: a 80B model
  pull is tens of gigabytes, and a machine that cannot hold it will produce a
  bad first run rather than an error.

### 5. No app at all — ship the Pi project

Distribute `.pi/` as a Pi project and skip the Mac shell. Saved workflows
register as slash commands (`/contract-review fixtures/example-nda.md`) and the
same SQLite store is written.

- **For:** near-zero packaging work; works wherever Pi works, including Linux.
- **Against:** loses the human-in-the-loop UI, which is the part that makes this
  a legal product rather than a script. From the TUI with no console attached,
  the mid-flow gate is skipped automatically — the attorney checkpoint is the
  app's reason to exist.
- **Worth doing anyway** as the low-effort distribution alongside (2): the
  workflows are the durable asset; the shell is a front end for them.

### Recommendation

The hardened-runtime question from (2) was the gate, because it decided whether
(2), (3) and (4) were possible at all. **It holds** (2026-09-30 spike above), so
the sequence is 2 → 4 → 3, with (5) published in parallel as the headless form.
The remaining work in (2) is the ordinary list — a Developer ID certificate, a
signing and notarization step in `scripts/build-app.sh`, resource embedding and
a first-run seed, an icon, a version scheme — and none of it requires changing
how `pi` is launched. Gatekeeper and notarization themselves are still untested;
no Developer ID certificate exists on the build Mac yet, and that is now the
first thing in the way.

## Where Pi sits in the OrchestratorAI offering

The offering already has a legal appliance: **orchestratorai-local**, the full
web platform. Pi is not a second one, and should not be sold as one.

| | orchestratorai-local | Pi |
|---|---|---|
| Shape | Web appliance, Postgres, multi-user | Single-user Mac app over an on-device SQLite store |
| Where the model runs | Deployment's choice | On the machine, via Ollama |
| Where the documents go | Into the appliance | Nowhere. They are read from disk by a local process |
| Who it is for | A firm | A practitioner, or an evaluator |

The distinct thing Pi has is **locality**: a matter can be run end to end on one
machine, with the documents never leaving it, and the run journal on disk to
inspect afterwards. That is a real answer to the confidentiality objection,
which is the first objection legal buyers raise. It is also what makes Pi a good
front door: it is the cheapest way for someone to see the workflows work before
committing to an appliance.

Three honest roles, in the order they are worth doing:

1. **Evaluation and demonstration.** The thing you put in front of someone.
   Fourteen workflows, synthetic fixtures, no deployment, no data leaving the
   room. This is the role it already fills and the only one it fills today.
2. **A local tier of the legal offering.** For work that must not leave the
   device. Requires (2) and (4) above, and a support answer for models.
3. **The reference implementation of the workflow catalog.** The
   `.pi/workflows/*.yaml` files are the asset — flow and launch UI in one file,
   consumable by any front end reading the same store. If the Apple lab or a
   web view later renders them, they read this store, not a new one.

What Pi is **not**, and should not be positioned as: a replacement for the
appliance; a multi-user system; a hosted service; a compliance control. The
Jev guard is a calibrated classifier on one step, not a compliance guarantee.

## Draft public wording

Draft. No traction, customer, usage or performance claims, because there are
none to make. Everything below is a description of what the software does.

> **OrchestratorAI Pi — legal workflows that run on your machine.**
>
> Pi is a local legal agent workspace for macOS. Fourteen composed workflows —
> contract review, due diligence, discovery review, deposition preparation,
> compliance audit and more — run against documents on your own disk, using a
> language model served locally. Documents are read by a local process and are
> not uploaded.
>
> Every workflow stops where a lawyer should be reading. Mid-flow gates hand
> counsel the work in progress and feed the decision and note back into the
> steps that follow; a final review records the decision against the report.
> Each run is journaled to an on-device store — every step, every intermediate
> output, the model used — so the work can be inspected after the fact, and a
> run interrupted part-way can be resumed from where it stopped.
>
> Pi is part of the OrchestratorAI legal offering, alongside the
> OrchestratorAI Local appliance for firm-wide deployment.

Shorter form:

> Fourteen legal workflows, a local model, and an attorney checkpoint in the
> middle of each one. Your documents stay on your machine.

### Claims, and what backs each one

Nothing in the wording above should ship without the line next to it.

| Claim | What backs it |
|---|---|
| "Fourteen composed workflows" | `.pi/workflows/*.yaml`; each is Ready in the app; see the click-through record |
| "run against documents on your own disk" | The launch card takes a file or folder path; the Pi process reads it directly |
| "not uploaded" | True of the workflow itself. **Caveat:** the `jev_check` guard calls a hosted endpoint. Either say so, make it optional, or move the rubric local before using this sentence |
| "using a language model served locally" | Ollama, provider `ollama` in `PiRunner` |
| "Mid-flow gates … feed the decision and note back" | `attorney_review` blocks the step and returns the decision verbatim; contract-review feeds it into summary generation |
| "journaled to an on-device store" | `data/orchestrator.sqlite`; `run_events`, `checkpoints`, `evaluations` |
| "can be resumed from where it stopped" | `/orchestrator resume`; verified by killing Pi at the contract-review gate |

### Words to avoid

"Secure", "compliant", "private by design", "trusted by", "used by", "saves N
hours", "accurate". The first three are claims about a system nobody has audited;
the rest are claims about a product nobody has used. None of them are needed —
"your documents stay on your machine" is both stronger and true.

## What this plan does not cover

- Pricing and licensing.
- The Apple catalog build, which is explicitly out of scope here.
- Any change to orchestratorai.io or orchestratorai-offering.
- A security review of the app or the extension. One should happen before
  anything is distributed outside the building — in particular the `.env`
  reader that hands `TYPESAFE_API_KEY` to the Pi process, and the fact that the
  app spawns an interpreter found on PATH.
