# OrchestratorAI - Pi data layout

```text
data/
├── orchestrator.sqlite   on-device run store (git-ignored; WAL sidecars alongside)
└── runs/                 legacy per-run directories from the file-based first version
```

## The run store

`orchestrator.sqlite` is written by the Pi extension (`.pi/extensions/orchestrator/`) and read by the macOS app. It holds three tables:

- `runs` — one row per launch: workflow, title, source document, params, engine status (`queued` → `running` → `completed` | `failed` | `stopped`), and the final Markdown/JSON result.
- `run_events` — the journal: every pi-agents run event with a human summary and, for completed nodes, the intermediate output.
- `checkpoints` — attorney decisions. `gate` rows pause a live workflow until decided; `final_review` rows are created when a run completes and record Approve / Request changes.

The app only ever writes checkpoint decisions and deletes; the engine journal belongs to Pi.

## Matters and private material

Real client documents and privileged material stay in ignored private directories (`matters/**/private/`, `fixtures/private/`) or outside the repository. Synthetic examples may be checked in. The store itself is ignored because run results may contain privileged content.
