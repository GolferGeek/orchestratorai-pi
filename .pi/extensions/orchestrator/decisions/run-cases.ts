// Labelled cases for the vendored rubrics, run live against the decision model.
// Usage (from .pi/extensions/orchestrator): DECISION_BASE_URL=http://gg-macstudio:11434 npm run cases -- [--model=clef-flash] [--rubric=name] [--dry]
// --dry validates every rubric and case file without calling the model.
import * as fs from "node:fs";
import * as path from "node:path";
import YAML from "yaml";
import { DecisionClient, runRubric } from "./index.ts";
import { loadRubricDir } from "./node.ts";

type Suite = { rubric: string; cases: Array<{ name: string; expect: string[]; state: string | Record<string, unknown> }> };

const piDir = path.resolve(import.meta.dirname, "..", "..", "..");
const casesDir = path.join(piDir, "rubric-cases");
const arg = (name: string) => process.argv.find((a) => a.startsWith(`--${name}=`))?.split("=")[1];
const dry = process.argv.includes("--dry");
const only = arg("rubric");
const model = arg("model");

const rubrics = loadRubricDir(process.env.DECISION_RUBRIC_DIR || path.join(piDir, "rubrics"));
const client = dry ? undefined : new DecisionClient(model ? { model } : {});
const covered = new Set<string>();
let total = 0, failed = 0;

for (const file of fs.readdirSync(casesDir).filter((f) => /\.ya?ml$/.test(f)).sort()) {
  const suite = YAML.parse(fs.readFileSync(path.join(casesDir, file), "utf8")) as Suite;
  if (only && suite.rubric !== only) continue;
  const rubric = rubrics.get(suite.rubric);
  if (!rubric) { console.log(`✗ ${file}: unknown rubric ${suite.rubric}`); failed++; continue; }
  covered.add(rubric.name);
  console.log(`\n${rubric.name} v${rubric.version}`);
  for (const c of suite.cases) {
    total++;
    if (!client) continue;
    try {
      const r = await runRubric(client, rubric, c.state);
      const ok = c.expect.includes(r.decision);
      if (!ok) failed++;
      console.log(`  ${ok ? "✓" : "✗"} ${c.name.padEnd(52)} ${r.decision.padEnd(6)} expected ${c.expect.join("|").padEnd(12)} (${r.reason}) [${r.model}]`);
    } catch (e) { failed++; console.log(`  ✗ ${c.name}: ${(e as Error).message}`); }
  }
}
// Every vendored rubric needs labelled cases; a rubric without them is untested.
const uncovered = only ? [] : [...rubrics.keys()].filter((name) => !covered.has(name));
for (const name of uncovered) console.log(`✗ ${name}: no labelled cases in ${casesDir}`);
console.log(`\n${total - failed}/${total} ${dry ? "validated" : "passed"}`);
process.exit(failed || uncovered.length ? 1 : 0);
