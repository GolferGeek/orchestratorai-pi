/**
 * Decision models (Clef on the Mac Studio's Ollama today) behind a provider-neutral
 * /v1/systemone client. Vendored so the extension has no sibling-repo dependency.
 * Imports carry .ts extensions so the same files load under Pi's jiti and plain Node.
 * The YAML loader is in ./node.ts, kept out of here so a missing `yaml` install cannot stop
 * the extension (run journal, attorney_review) from loading.
 */
export * from "./types.ts";
export { DecisionClient, DecisionError, DEFAULT_DECISION_MODEL, toRawBase64, type DecisionClientOptions, type DecisionModel } from "./client.ts";
export { type Rubric, type RubricInput, type RoutingRule, type RubricResult, type Decision, validateRubric, route, runRubric, composeState, splitImages } from "./rubric.ts";
