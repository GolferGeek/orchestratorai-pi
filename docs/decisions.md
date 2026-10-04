# Decision rubrics (`jev_check`)

Some steps are checked by a decision model instead of a prompt. The `jev_check` tool runs a named
rubric (a fixed set of yes/no, choice, and score questions plus routing rules) and returns one of
three decisions:

- `pass`: the content can be used.
- `review`: a person should look at it first.
- `block`: do not use it.

The tool keeps its old name, and the `jev-gate` profile keeps its name too, because the workflows and
stored runs refer to both. Today the questions are answered by **Clef**, the decision model served by
Ollama on the Mac Studio.

## Pieces

| Path | What it is |
|---|---|
| `.pi/extensions/orchestrator/decisions/` | Vendored `/v1/systemone` client, rubric loader, and router. It has no dependencies other than `yaml`. |
| `.pi/rubrics/<group>/*.yaml` | The rubrics: `guards/witness-coaching`, `compare/citation-in-record`, `scoring/severity-normalize`, `coding/privilege-coding`, `coding/signal-classify`. |
| `.pi/rubric-cases/*.yaml` | Labelled cases. Each case lists the decisions it accepts. Every rubric needs at least one case file. |
| `.pi/agents/jev-gate.md` | The checkpoint persona. Its only tool is `jev_check`. It calls the tool once and returns the decision unchanged. |
| `evaluations` table | Every check, with its answers, model, and token counts. The app's Evaluations card and the run badges read this table. |

## Configuration

The extension reads these variables from the environment. The macOS app passes the project's `.env`
to Pi. In a terminal, export them before you run `pi`.

| Variable | Default | Meaning |
|---|---|---|
| `DECISION_BASE_URL` | none (required) | The endpoint. On the Studio it is `http://127.0.0.1:11434`. From another machine on the tailnet it is `http://gg-macstudio:11434`. If it is not set, `jev_check` returns an error, never a decision. |
| `DECISION_MODEL` | `clef` | `clef` or `clef-flash`. |
| `DECISION_API_KEY` | empty | Sent as a Bearer token when set. Ollama ignores it. A hosted endpoint needs it. |
| `DECISION_TIMEOUT_MS` | `120000` | Loading Clef cold takes tens of seconds. |
| `DECISION_RUBRIC_DIR` | `.pi/rubrics` | Use a different rubric folder, for example one you are trying out. |

The client is not tied to Ollama. It needs any endpoint that speaks `/v1/systemone`. Moving to hosted
Jev later should only need `DECISION_BASE_URL`, `DECISION_API_KEY`, and `DECISION_MODEL`.

## How deposition-prep uses it

The answer-preparation step is an LLM. Prompt rules could not stop the local model from writing
testimony for the witness, so the step's output now goes through `witness-coaching`. The workflow
then switches on the decision:

- `pass`: the text is included.
- `review`: the attorney sees it at a gate before it is included.
- `block`: the text is left out, and the report says why.

## Labelled cases

The runner is TypeScript that Node runs directly, so it needs Node 22.18 or later.

```sh
cd .pi/extensions/orchestrator
npm install                                                # once: installs yaml
DECISION_BASE_URL=http://gg-macstudio:11434 npm run cases  # live, against clef
npm run cases -- --dry                                     # validate rubrics and cases only
npm run cases -- --model=clef-flash --rubric=witness-coaching
```

Results on 2026-10-04:

- `clef`: 29/29, in about a minute.
- `clef-flash`: 22/29. It misses the invented-date citation, some witness-coaching cases, and
  privilege coding. Keep `clef` for these legal rubrics.

When you change a rubric, increase its `version`. The version is stored with every evaluation.
