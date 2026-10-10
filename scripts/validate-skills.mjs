#!/usr/bin/env node
// Validates every skills/*/SKILL.md against the agent skill format:
// - YAML frontmatter with string `name` and `description`
// - name matches directory name, lowercase [a-z0-9-], <= 64 chars
// - description <= 1024 chars
import { readdir, readFile } from "node:fs/promises";
import { join, basename } from "node:path";

const skillsDir = join(process.cwd(), "skills");
const NAME_RE = /^[a-z0-9][a-z0-9-]*$/;
const errors = [];

const dirs = (await readdir(skillsDir, { withFileTypes: true }))
  .filter((e) => e.isDirectory())
  .map((e) => e.name);

for (const dir of dirs) {
  const skillMdPath = join(skillsDir, dir, "SKILL.md");
  let content;
  try {
    content = await readFile(skillMdPath, "utf-8");
  } catch {
    errors.push(`${dir}: missing SKILL.md`);
    continue;
  }

  const match = content.match(/^---\n([\s\S]*?)\n---/);
  if (!match) {
    errors.push(`${dir}: SKILL.md has no frontmatter block`);
    continue;
  }
  const frontmatter = match[1];

  const field = (key) => {
    const m = frontmatter.match(new RegExp(`^${key}:\\s*(.+)$`, "m"));
    if (!m) return undefined;
    let v = m[1].trim();
    if ((v.startsWith(`"`) && v.endsWith(`"`)) || (v.startsWith(`'`) && v.endsWith(`'`))) {
      v = v.slice(1, -1);
    }
    return v;
  };

  const name = field("name");
  const description = field("description");

  if (!name) errors.push(`${dir}: missing frontmatter field "name"`);
  if (!description) errors.push(`${dir}: missing frontmatter field "description"`);
  if (typeof name !== "string") continue;

  if (name !== dir) errors.push(`${dir}: name "${name}" does not match directory name "${dir}"`);
  if (!NAME_RE.test(name))
    errors.push(`${dir}: name "${name}" must be lowercase alphanumeric/hyphens`);
  if (name.length > 64) errors.push(`${dir}: name exceeds 64 chars`);
  if (description && description.length > 1024) errors.push(`${dir}: description exceeds 1024 chars`);
}

if (dirs.length === 0) errors.push("no skills found under skills/");

if (errors.length > 0) {
  for (const e of errors) console.error(`✗ ${e}`);
  console.error(`\nValidation failed with ${errors.length} error(s).`);
  process.exit(1);
}

console.log(`✓ ${dirs.length} skill(s) validated successfully.`);
