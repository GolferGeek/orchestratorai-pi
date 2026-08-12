# OrchestratorAI - Pi data layout

The first version uses files rather than a database. The layout separates stable definitions from matter material and time-based execution records.

```text
data/
├── catalog/
│   ├── categories/
│   ├── workflows/
│   ├── agents/
│   └── skills/
├── matters/
│   └── <matter-slug>/
│       ├── matter.md
│       ├── documents/
│       ├── instructions/
│       └── reviews/
└── runs/
    └── YYYY/
        └── MM/
            └── YYYY-MM-DD/
                └── <run-id>/
                    ├── manifest.json
                    ├── request.md
                    ├── trace.md
                    ├── thinking.md
                    ├── final.md
                    └── checkpoints/
                        └── 01-attorney-review.yaml
```

## What belongs where

- `catalog/` contains reusable workflow, agent, skill, and category definitions. These are stable and should not move merely because they were used on a particular date.
- `matters/` contains the legal context and source documents for a matter. Matter folders use meaningful names rather than dates.
- `runs/` contains immutable execution evidence. Runs are partitioned by year, month, and date so they remain easy to browse and archive.

Use ISO dates and stable slugs. Give every run a unique ID, such as `2026-08-10T091530Z-contract-review-01`, even when the folder already contains the date.

Every run also needs a human-readable title. A title should begin with the workflow kind and identify the primary document or effort, for example `Contract review — Mutual NDA` or `Policy comparison — Data retention policy`. Store that title in `manifest.json` and use it for the Pi session name and exported report filename.

The run status moves through values such as `running`, `awaiting_human_review`, `revision_requested`, and `completed`. The checkpoint YAML records the human decision without modifying the original document.

Real client documents and privileged material should remain in ignored private directories or outside the repository. Synthetic examples and reusable definitions may be checked in.
