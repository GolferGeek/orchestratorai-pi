# Jev (TypeSafe AI) — documentation mirror and integration notes

Verbatim mirror of https://docs.typesafe.ai fetched 2026-09-19 (58 pages, `llms.txt` index at
https://docs.typesafe.ai/llms.txt). Re-fetch with the Python snippet at the bottom when the docs move.

## What Jev is, in one paragraph

A "System One" model: instead of generating text, it answers **typed questions** about a piece of
content (the *state*) and returns **calibrated probabilities**. No hallucination surface — every answer
is one of the options you defined. It is ~200× faster and ~400× cheaper than an LLM on decision tasks, so
it can sit inside a loop, in front of every LLM output, or across a whole corpus.

## The three primitives (the entire API)

| Primitive | Ask | Returns | Use it for |
|---|---|---|---|
| **Noul** | "Is this statement true?" | `noul` — probability 0–1 | yes/no gates, guardrails, fact checks |
| **Choice** | "Which of these options?" | `choice` + `probabilities` + `confidence` | classification, routing, coding |
| **Score** | "Where on this rubric?" | `score` (probability-weighted) + `probabilities` + `confidence` | severity, quality, ranking |

All three can be mixed in **one request**; each question is evaluated in parallel and in isolation.
Full detail: [primitives/README.md](primitives/README.md), [choice](primitives/choice.md),
[score](primitives/score.md), [noul](primitives/noul.md).

## Calling it

```http
POST https://api.typesafe.ai/v1/systemone
Authorization: Bearer $TYPESAFE_API_KEY
Content-Type: application/json

{ "state": "<text or JSON to evaluate>",
  "model": "jev-latest",
  "questions": {
    "is_coaching": { "type": "noul", "instructions": "Does this text supply answers or framing for a witness to adopt?" },
    "privilege":   { "type": "choice", "instructions": "Privilege status", "criteria": { "privileged": "…", "not_privileged": "…", "potentially_privileged": "…" } },
    "severity":    { "type": "score", "instructions": "How severe?", "criteria": ["Cosmetic", "Degraded, workaround exists", "Blocking"] }
  } }
```

Response: `{ "model", "answers": { "<id>": { "type", "noul"|"choice"|"score", "probabilities", "confidence" } }, "usage" }`.
Reference: [api.md](api.md). SDKs: `npm install @typesafe-ai/sdk` ([sdk/javascript.md](sdk/javascript.md)),
`pip install typesafe-sdk` ([sdk/python.md](sdk/python.md)). The env var both SDKs read is
`TYPESAFE_API_KEY`. Node ≥ 20 has `fetch`, so the extension calls the HTTP API directly.

## Confidence — the part that matters for HITL

Every Choice and Score answer carries `confidence` (0–1), derived from how concentrated the probability
distribution is. The documented pattern ([confidence.md](confidence.md)) is three ranges:
**high → act automatically · medium → proceed with caution / ask · low → do not act, route to a human.**
Thresholds scale with stakes. In this project that maps one-to-one onto the existing gate: a workflow
node can call Jev first and only open an `attorney_review` checkpoint when confidence is in the middle.

## Cookbooks that map onto this project's known defects

| Cookbook | Defect it addresses here |
|---|---|
| [llm-guardrails](cookbooks/llm-guardrails.md) | Deposition prep generated witness coaching; three prompt fixes failed and the step was cut. A Noul battery over each output ("supplies answers for a witness?", "characterises what a document meant?") with `review`/`action` thresholds is the guard that prompts could not be. |
| [citation-check](cookbooks/citation-check.md) | Brief Stress Test and Legal Research emit `[VERIFY]` on authorities they cannot verify; the deal memo invented a date. A per-citation Noul ("is this authority present in the supplied record?") makes that check mechanical. |
| [classification-using-confidence](cookbooks/classification-using-confidence.md) | Discovery Review's privilege call is category + a 0.95 threshold — exactly this cookbook. Today a 36B generalist self-reports confidence; Jev returns a calibrated one. |
| [hierarchical-classification](cookbooks/hierarchical-classification.md) | Sentinel's type → jurisdiction → practice-area classification. |
| [self-consistency-nouls](cookbooks/self-consistency-nouls.md) / [-choices](cookbooks/self-consistency-choices.md) | Regression grading: same fixture, same questions, compare runs after a prompt change. |
| [parallel-questions](cookbooks/parallel-questions.md) | Fan a whole rubric over one report in one call. |
| [rerank](cookbooks/rerank.md), [classifying-rag-passages](cookbooks/classifying-rag-passages.md) | Legal Research / KB Query retrieval over the knowledge folder. |

Patterns worth reading before designing a node: [confidence-routing](patterns/confidence-routing.md),
[composite-scoring](patterns/composite-scoring.md), [fan-out](patterns/fan-out.md).
Known model quirks: [jev-1.13-jaggedness.md](jev-1.13-jaggedness.md).

## Where it plugs into orchestratorai-pi

1. **Evaluator layer** — an `evaluations` table in `data/orchestrator.sqlite` keyed by `run_id` / `seq`,
   populated by the extension after each `node_completed`, so every agent output gets a rubric score and
   the app can badge runs that fail a check. The store already holds every node's output
   (`run_events.detail`), so this also works retroactively over past runs.
2. **In-flow gates** — a `jev_check` tool registered by the extension (same pattern as `attorney_review`)
   that a workflow node calls with the questions to ask; `switch` / `until` predicates route on the answer.
3. **Conditional HITL** — `attorney_review` opens only when Jev's confidence is in the review band.
4. **Regression harness** — fixtures with known planted answers (the deal room has six critical risks, the
   discovery corpus four privileged/borderline documents) graded by the same questions after every change.

## Re-fetching this mirror

```python
import urllib.request, os
B = "https://docs.typesafe.ai/"
index = urllib.request.urlopen(B + "llms.txt").read().decode()
# each line of llms.txt that contains a .md URL → fetch and save under docs/jev/ preserving the path
```
