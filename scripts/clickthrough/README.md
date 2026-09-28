# Click-through harness

Drives the built `dist/Pi.app` through macOS accessibility, so a verification run
is a record of real clicks rather than a claim about them. Written for
[docs/verification/2026-09-28-clickthrough.md](../../docs/verification/2026-09-28-clickthrough.md)
and kept so the next pass is repeatable.

## Why it is shaped like this

Two macOS facts drive the design:

1. **Accessibility is granted per responsible process.** A shell launched from
   `launchd` (an automated handoff, a `claude -p` job) is not in the
   Accessibility list, so `osascript` and the AX APIs refuse. `worker.sh` is
   started *inside Terminal.app* (`osascript -e 'tell application "Terminal" to
   do script "…/worker.sh"'`), and everything it runs inherits Terminal's grant.
   `r` is the client: it drops a command in `/tmp/pidrv/in.sh` and waits for the
   worker's output. Grant Terminal (or whichever terminal you use) Accessibility
   in System Settings → Privacy & Security first.

2. **A window on another Space is invisible to `System Events`.** `Pi` opens
   full-screen, so `count of windows of process "Pi"` is `0` whenever Pi is not
   frontmost. Every `axdrv` command activates Pi before it reads the tree.

## Pieces

| File | What it does |
|---|---|
| `worker.sh` | The Terminal-hosted loop. Runs whatever `r` queues, writes stdout/rc back. |
| `r` | Client for the worker: `r <command…>`, prints its output, returns its exit code. |
| `axdrv.swift` | The driver. Walks the AX tree, clicks, types, scrolls, reads values. |
| `d` | `r … axdrv` shorthand: `d press launch.start`, `d text`, `d ids`. |
| `t` | `t <identifier> <text>` — click a field, select all, type over it. |
| `k` / `keys.scpt` | Raw keys (`esc`, `return`, `clear`) via System Events. |
| `decideloop.sh` | The shared watch-and-decide loop: answers whatever a run is waiting on — a mid-flow gate, the final review — with real clicks. |
| `runwf.sh` | One workflow end to end: select → new run → demo sample → Start, then `decideloop.sh`. |
| `reviewrun.sh` | Finishes a run that already exists: resumes it if nothing is driving it, then `decideloop.sh`. |

## Setup

```sh
mkdir -p /tmp/pidrv && cp scripts/clickthrough/* /tmp/pidrv/
cd /tmp/pidrv && swiftc -O axdrv.swift -o axdrv
osascript -e 'tell application "Terminal" to do script "/tmp/pidrv/worker.sh"'
./scripts/build-app.sh && open dist/Pi.app
```

## Using it

```sh
/tmp/pidrv/d ids                      # every accessibility identifier on screen
/tmp/pidrv/d text                     # every static text, for asserting copy
/tmp/pidrv/d press launch.start       # AXPress, falling back to a real click
/tmp/pidrv/d click sidebar.workflow.contract-review
/tmp/pidrv/d choose context.field.reviewer_side "Disclosing party"
/tmp/pidrv/t  context.model "qwen3.6:latest"
/tmp/pidrv/runwf.sh contract-review "Reviewed; proceed." 45
```

`runwf.sh` reads `data/orchestrator.sqlite` only to decide *when* to look at the
screen. Every decision it records — each gate, each final review — is a click on
the card, and it asserts the card is on screen before clicking.

## Traps worth knowing

- **`AXValue` set ≠ typed.** `AXUIElementSetAttributeValue(kAXValue…)` changes
  what a SwiftUI `TextField` displays without firing its binding, so the app's
  state never updates. Only real keystrokes (`t`) work. `axdrv set` is kept for
  reading-back experiments; do not verify with it.
- **Off-screen controls swallow clicks.** The detail pane is a `ScrollView` that
  does not implement `AXScrollToVisible`, so `Approve review` sat below the
  display edge and clicks landed on nothing — with no error. `clickEl`
  scroll-wheels the element into the visible area first. Always assert the
  post-state (the checkpoint row, the counter), never just the click's "OK".
- **Some borderless buttons ignore synthetic clicks.** `Save Markdown` only
  responds to `AXPress`. `press` tries `AXPress` first, then a click.
- **An identifier on a container replaces its descendants'.** A
  `.accessibilityIdentifier` on a row overwrites the identifiers of buttons
  inside it, so a declared identifier can be dead. `d ids` is the check.
- **Sidebar sections only expose their collapse control on hover:**
  `d hover AXHeading Litigation` then `d click NSOutlineViewShowHideButtonKey`.
- **One live run disables Start for every other workflow.** So a run the harness
  fails to finish does not fail one line of the record — it fails every line
  after it. That is why the gate and final-review logic is in one shared
  `decideloop.sh` instead of duplicated: the first pass lost four hours to a
  `reviewrun.sh` that only knew how to answer a final review, meeting a run that
  had stopped at a mid-flow gate. When `runwf.sh` reports that Start never
  became enabled, it now names the run still holding the app.
