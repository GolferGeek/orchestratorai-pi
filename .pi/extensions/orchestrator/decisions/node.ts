/**
 * Node-only helpers: load rubrics from a directory of YAML files. Kept out of
 * index.ts so the rest stays fs-free.
 */
import * as fs from "node:fs";
import * as path from "node:path";
import YAML from "yaml";
import { validateRubric, type Rubric } from "./rubric.ts";

export function loadRubricFile(file: string, group?: string): Rubric {
  const parsed = YAML.parse(fs.readFileSync(file, "utf8")) as Record<string, unknown>;
  // The folder is the bucket; a file may state its group but it must agree.
  if (group) {
    if (parsed.group !== undefined && parsed.group !== group) throw new Error(`${file}: group '${parsed.group}' disagrees with folder '${group}'`);
    parsed.group = group;
  }
  validateRubric(parsed);
  return parsed;
}

/**
 * Load rubrics/<group>/*.yaml. Top-level files are allowed only if they declare
 * their own group. Keyed by name; names must be unique across groups.
 */
export function loadRubricDir(dir: string): Map<string, Rubric> {
  const out = new Map<string, Rubric>();
  if (!fs.existsSync(dir)) return out;
  const add = (rubric: Rubric, from: string) => {
    if (out.has(rubric.name)) throw new Error(`duplicate rubric name ${rubric.name} (${from})`);
    out.set(rubric.name, rubric);
  };
  for (const entry of fs.readdirSync(dir, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      for (const f of fs.readdirSync(full).sort()) if (/\.ya?ml$/.test(f)) add(loadRubricFile(path.join(full, f), entry.name), `${entry.name}/${f}`);
    } else if (/\.ya?ml$/.test(entry.name)) {
      add(loadRubricFile(full), entry.name);
    }
  }
  return out;
}

/** Rubrics grouped by bucket, for catalogs. */
export function groupRubrics(rubrics: Map<string, Rubric>): Map<string, Rubric[]> {
  const g = new Map<string, Rubric[]>();
  for (const r of rubrics.values()) g.set(r.group, [...(g.get(r.group) ?? []), r]);
  return g;
}
