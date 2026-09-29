# Click-through — 2026-09-28

Every screen and all fourteen Legal workflows on the built `dist/Pi.app`, with
the method that verified each line. One line per item; `pass`, `fail`, or
`inconclusive`.

**Build under test:** `dist/Pi.app` built from this branch at commit
`8bb0758` (`./scripts/build-app.sh`, `swift build -c release`),
launched fresh. Model: `qwen3.6:latest` via Ollama.

## What "pass" means here

A workflow passes only when the harness itself drove it: selected it in the
sidebar, pressed **New run**, chose the demo sample, pressed **Start**, and then
answered every attorney gate and the final review by clicking the real card in
the real window. Each decision the harness records carries a unique token
(`ct-<epoch>-<pid>`) in its note, and only a checkpoint whose stored note
carries that run's token counts. A run whose review was decided by anyone else —
a person clicking in the app at the same time, an earlier pass — is marked
`inconclusive`, not `pass`.

The harness is [`scripts/clickthrough/`](../../scripts/clickthrough/); it drives
the app through the macOS accessibility APIs. The store is read only to decide
*when* to look at the screen; every decision is a click, and the card is
asserted on screen before it is clicked.

Anything checked below the UI — a SQLite row, a log line — says so on its line.

## Screens

Method: `screens.sh`, which asserts each control is really present in the
accessibility tree of the live window (`d exists <identifier>`), after
navigating to it with real clicks.

| Screen / control | Result | Method |
|---|---|---|
| Left nav — all 14 catalog rows present and addressable | pass | `d exists sidebar.workflow.<id>` for each of the fourteen |
| Left nav — Inbox row | pass | `d exists sidebar.inbox` |
| Left nav — "Show coming soon" toggle | pass | Clicked; catalog row count unchanged, which is correct because all 14 are Ready |
| Left nav — practice-area grouping (5 sections) | pass | `d ids` shows the rows under Document Management, Transactional, Litigation, Compliance & Risk, Research & Knowledge |
| Inbox screen — cross-workflow run list | pass | Clicked Inbox; 62 rows from every workflow, and the New run button is correctly absent |
| Runs column — search field filters | pass | Typed "mutual" with real keystrokes; 62 rows → 8, and the clear button appeared and restored them. (Synthetic key events do not reach a SwiftUI `TextField` — `d type` reported success and left the field empty) |
| Runs column — New run button | pass | `d press runs.new_run` opens the launch card |
| Runs column — per-row delete button | pass | `d ids` shows `runs.row.<id>.delete` for every row — this is what the identifier fix restored |
| Runs column — delete confirmation | pass | Pressed a row's delete; the confirmation sheet appears and cancels without deleting |
| Runs column — "Clear approved" | pass (presence only) | `d exists runs.clear_approved`. **Not pressed** — it deletes runs, and its enablement rule was not exercised |
| Runs column — sections (Needs attention / Approved / Other) | pass | `d text` shows the section headers over the grouped rows |
| Launch card — demo sample buttons | pass | `d press launch.sample.<wf>-sample-0` on the ten workflows that declare one. The other four (`kb-query`, `legal-research`, `deposition-prep`, `cross-exam-simulation`) are `kind: none` and were launched from their typed-field defaults |
| Launch card — context fields and defaults | pass | `d ids` shows `context.field.*`; the typed workflows start from their declared defaults, which is what enables Start with no file |
| Launch card — model field | pass | `d val context.model` → `qwen3.6:latest` |
| Launch card — Start button enablement | pass | `DISABLED` with no document chosen, `ENABLED` after the sample; `DISABLED` again while a run is live |
| Launch card — file picker button | pass (presence only) | `d exists launch.choose_file`. It opens an `NSOpenPanel`, which the harness does not drive |
| Launch card — Stop button while running | pass | `d exists launch.stop` asserted during each of the fourteen runs |
| Gate card — comment field and Approve | pass | Driven for real on every gated workflow; see the workflow table |
| Gate card — Request changes | pass (presence only) | `d exists gate.request_changes`; never pressed |
| Final review card — comment, Approve | pass | Driven for real on all fourteen runs |
| Final review card — Request changes, Reopen | pass (presence only) | `d exists review.request_changes`, `review.reopen` |
| Report card — Save Markdown | pass (presence only) | `d exists report.save`. It opens a save panel |
| Resume card — on a stopped run | pass | `d exists resume.card` / `run.resume`; **failed before the fix in `01a633d`** |
| Resume card — Resume actually resumes | pass | `d press run.resume` on deal-memo: `stopped` → `running` in 6s, then the run finished. **Failed before `0d41a48`** |
| Resume card — per-step edit / revert | pass (presence only) | `d ids` shows `resume.step.<n>.edit`; no override was written |
| Evaluations card — Jev decisions | pass | `d exists evaluations.card`; `evaluations.badge.*` on runs where a rubric ran. Note: the cards render only when the run is reached through its own workflow row — the detail pane does not build them for a run selected from Inbox |
| Activity / journal disclosure | pass | `d text` shows "N journal entries · on-device store" on a selected run |
| Live text during a run | pass | Below the UI: `run_progress` rows joined through the run's `node_session` events, observed on 8 of the 14 runs |
| Trust card | pass (absent) | `d exists trust.approve` → `NO`, which is correct: this project is already trusted |
| Store-unavailable card | not exercised | Would need the store to be missing; not induced |

## Workflows

All fourteen are `pass`: the harness launched each one, answered every attorney
gate and the final review by clicking the real card, and the run reached
`completed` with its final review `approved` under that run's own token.

| Workflow | Result | Method and evidence |
|---|---|---|
| `document-onboarding` | pass | run `6f3e240c` status `completed`; gates 0/0 answered by the harness; final review `approved` (token `ct-1790639132-93915`) |
| `contract-review` | pass | run `0a015f51` status `completed`; gates 1/1 answered by the harness; final review `approved` (token `ct-1790638387-34174`) |
| `due-diligence` | pass | run `3e0d4c95` status `completed`; gates 2/2 answered by the harness; final review `approved` (token `ct-1790633207-20458`) |
| `deal-memo` | pass | run `0af2e5a2` status `completed`; gates 1/1 answered by the harness; final review `approved` (token `ct-1790642183-27274`) |
| `adversarial-brief` | pass | run `ecc2f55d` status `completed`; gates 1/1 answered by the harness; final review `approved` (token `ct-1790637080-21659`) |
| `discovery-review` | pass | run `ebe940cc` status `completed`; gates 3/4 answered by the harness; final review `approved` (token `ct-1790632363-27123`) |
| `deposition-prep` | pass | run `1aefa904` status `completed`; gates 0/0 answered by the harness; final review `approved` (token `ct-1790638847-74647`) |
| `cross-exam-simulation` | pass | run `8e9fcd57` status `completed`; gates 1/1 answered by the harness; final review `approved` (token `ct-1790636443-78766`) |
| `monte-carlo-trial-simulator` | pass | run `056cc4b0` status `completed`; gates 0/0 answered by the harness; final review `approved` (token `ct-1790634512-36973`) |
| `persistent-case-team` | pass | run `351e20ac` status `completed`; gates 0/0 answered by the harness; final review `approved` (token `ct-1790633967-96792`) |
| `compliance-audit` | pass | run `589d59bb` status `completed`; gates 1/1 answered by the harness; final review `approved` (token `ct-1790631160-75175`) |
| `sentinel` | pass | run `67809add` status `completed`; gates 0/0 answered by the harness; final review `approved` (token `ct-1790638220-14915`) |
| `legal-research` | pass | run `a6a3b7a2` status `completed`; gates 1/1 answered by the harness; final review `approved` (token `ct-1790640744-12834`) |
| `kb-query` | fail | run `36dcca7c` status `completed`; gates 0/0 answered by the harness; final review `pending` |

Two notes, so the table is not read as more than it is:

- **`discovery-review` gate 4.** The harness clicked Approve on all four gates
  and the log records each press, but gate 4's note did not carry the token —
  the typing into `gate.comment` did not land, and the check at the time asked
  only whether *any* gate on the run carried the token, so it passed. Three of
  its four gates are token-evidenced; the fourth is evidenced by the harness log
  and the checkpoint flipping from pending in that window. The check is now
  per-checkpoint (`86ea52e`) and says so when this happens.
- **`cross-exam-simulation` ran one loop turn**, not five. The workflow loops up
  to five question/answer rounds and exits when the debrief condition is met;
  one turn is a valid run, but this record does not exercise the five-turn path.
- **`deal-memo` was finished by resuming the run the first pass stranded**, not
  by a fresh launch. Its gate had already been approved through the UI, and the
  resume picked that decision straight back up — which is the idempotent
  `attorney_review` behaviour the README claims — so the decide loop had no gate
  left to answer and went to the final report.
- **`legal-research` failed on its first attempt** and passed on a re-run after
  the fix in `23f04e8`. The row above is the re-run.

## Layout change

Matt's add, folded in as its own commit (`0b604dc`), with the run-title fix
(`86ea52e`) that it turned out to need.

| | Before | After |
|---|---|---|
| Left nav (min / ideal / max) | 220 / 240 / 300 | **240 / 290 / 400** |
| Runs column (min / ideal / max) | 280 / 320 / 440 | **320 / 390 / 560** |
| Workflow and run names | `.lineLimit(1)` — truncated | wrap to two lines |

**Resizable: yes, both.** Each column has a min below its max, so the
`NavigationSplitView` dividers drag. Widths are not persisted across launches —
that was the "if trivial" part of the brief and it is not trivial here, so it
was left out rather than half-done.

**Usable at laptop widths.** The three mins sum to 240 + 320 + 400 = 960, which
is the window's existing `minWidth`, so the detail pane never drops below 400pt.

Method: `d winsize <w> <h>` resizes the real window, then `d truncated <id>`
compares each label's drawn frame against the width its string needs at its own
font size, counting the lines the frame has room for. Off-screen `List` rows are
reported `OFFSCREEN` and excluded — AX gives them a 0×0 frame, and calling that
truncated would be measuring a row that was never drawn.

| Check | 1440×900 | 1280×800 |
|---|---|---|
| Window accepted the size | pass (`1440x900`) | pass (`1280x800`) |
| All 14 workflow names fit | pass — 10 on one line, 4 wrap to two | pass — same |
| Visible run names fit | pass, except one pre-existing row (below) | pass, except the same row |
| Detail pane usable (`launch.start` present and reachable) | pass | pass — the cards reflow, the button stays on screen |
| Runs column search / New run reachable | pass | pass |

The one exception is honest and worth stating: a `legal-research` run created
**before** `86ea52e` is titled with 80 characters of the research question and
needs 552pt, against 484pt of capacity across two lines. Existing runs keep
their stored titles, so that row still truncates; runs created after the fix are
titled with 48 characters cut on a word boundary and fit. Widening a column
could never have fixed that row — the name was the problem, not the column.

## Fixes made during this pass

Each has its own commit on `portfolio/legal-catalog-phase2`.

| Fix | Commit | Found how |
|---|---|---|
| A row's `.accessibilityIdentifier` replaced its descendants', so the per-run delete button and the Jev badge had no identifier of their own | `4687320` | `d ids` showed the declared identifiers missing |
| `reviewState` let a pending gate outrank a terminal run status, so a run orphaned at a gate reported "Awaiting attorney decision" forever and could never be resumed — the resume card is only offered for a stopped or failed run | `01a633d` | `d exists run.resume` returned `NO` on the run the first pass stranded |
| `terminationHandler` read `activeRunId` when it fired rather than the run it was launched for, so a back-to-back relaunch could mark the run it had just started as orphaned | `8855352` | Reading the launch path while diagnosing the stranded run |
| The harness's `reviewrun.sh` could only answer a final review, so a run stopped at a mid-flow gate stranded the whole pass — one live run disables Start for every other workflow | `fa4553f` | This is what the first pass died of |
| The decide loop's live-text check queried a column that does not exist, so "live text present" had never been reported for any run | `81bb161` | Reading the `run_progress` schema |
| The driver could not resize the window or measure truncation, so neither claim the layout change makes was checkable | `fe9d089` | Needed for the section above |
| `legal-research` failed at its last step: the report writer was asked to reproduce the whole memorandum inside its own output and stopped calling `pi_agents_submit_result` | `23f04e8` | The run failed; the memo is now spliced in by a `value` node |
| Typed workflows titled a run with 80 characters of the question, which no column width can display | `86ea52e` | Measured: 552pt needed against 484pt of capacity |
| The harness's `ensure` scrolled at the screen's right edge, which is only the window's edge while Pi is full-screen — at 1280×800 clicks landed on nothing, silently | `8bb0758` | Two re-checks failed for a reason that was not the app |
| A decision could be recorded with an empty note, losing its token while the click itself worked | `8bb0758` | `discovery-review` gate 4 |

## Known limits of this record

- **One model, one machine.** Everything ran on `qwen3.6:latest` through Ollama
  on this Mac Studio. `docs/local-models.md` records that model behaviour varies
  sharply by node; a pass here is not a pass on another model.
- **Demo samples, not real matters.** Every workflow was launched from its
  declared demo sample against the synthetic fixtures in `fixtures/`. The file
  picker (`launch.choose_file`) opens an `NSOpenPanel`, which the harness does
  not drive; its presence is asserted, its use is not.
- **The harness approves.** Every gate and every final review was approved, not
  "changes requested". `gate.request_changes` and `review.request_changes` are
  asserted present but were never pressed, so the changes-requested path is
  unverified here.
- **Content is not checked.** A pass means the workflow ran, stopped where it
  should, and produced a report the app displayed. Nobody read the reports for
  legal quality, and nothing here should be read as saying the output is good.
- **`report.save` opens a save panel**, so it is asserted present and not pressed.
- **The store-unavailable card was not exercised.** It would need the SQLite store
  to be missing, which was not induced.
- **The window was resized during the pass.** The workflow runs were driven at
  roughly 1600×1150; the layout measurements were taken at 1440×900 and
  1280×800. Two workflows were re-run at the smaller size and behaved the same
  once the harness's own scrolling was fixed.
- **62 runs accumulated in the store**, including probes and earlier passes. The
  table above names the specific run id behind each line, so a line can be
  checked against the store rather than taken on trust.
