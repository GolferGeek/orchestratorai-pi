---
name: contract-segmentation
description: Segment a contract into legally meaningful sections for parallel review while preserving source references and short excerpts.
---

# Contract segmentation

Return a JSON object with a `sections` array. Each section must contain:

- `id` — stable identifier such as `sec-001`
- `heading` — source heading or a descriptive label
- `location` — page, line, paragraph, or source-file reference when available
- `text` — the minimum excerpt needed for a reviewer to analyze the section
- `topics` — likely topics such as confidentiality, payment, termination, or liability

Keep definitions with the clauses that depend on them when possible. Keep schedules and signature blocks as separate sections. Do not silently omit provisions.

