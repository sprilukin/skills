#!/usr/bin/env node
// Validates every skills/**/SKILL.md against the agent skill format:
// - YAML frontmatter with string `name` and `description`
// - name matches directory name, lowercase [a-z0-9-], <= 64 chars
// - description <= 1024 chars
// Skills may be nested in category dirs, e.g. skills/general-purpose/git-ops/.
import { readdir, readFile } from "node:fs/promises";
import { join, basename, relative } from "node:path";

const skillsDir = join(process.cwd(), "skills");
const NAME_RE = /^[a-z0-9][a-z0-9-]*$/;
const errors = [];

// Collect directories containing a SKILL.md, at any depth under skills/.
async function findSkillDirs(dir) {
  const out = [];
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    const child = join(dir, entry.name);
    const entries = await readdir(child, { withFileTypes: true });
    if (entries.some((e) => e.isFile() && e.name === "SKILL.md")) out.push(child);
    out.push(...(await findSkillDirs(child)));
  }
  return out;
}

const dirs = await findSkillDirs(skillsDir);

for (const dir of dirs) {
  const label = relative(skillsDir, dir);
  const skillMdPath = join(dir, "SKILL.md");
  let content;
  try {
    content = await readFile(skillMdPath, "utf-8");
  } catch {
    errors.push(`${label}: missing SKILL.md`);
    continue;
  }

  const match = content.match(/^---\n([\s\S]*?)\n---/);
  if (!match) {
    errors.push(`${label}: SKILL.md has no frontmatter block`);
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

  const dirName = basename(dir);
  if (!name) errors.push(`${label}: missing frontmatter field "name"`);
  if (!description) errors.push(`${label}: missing frontmatter field "description"`);
  if (typeof name !== "string") continue;

  if (name !== dirName)
    errors.push(`${label}: name "${name}" does not match directory name "${dirName}"`);
  if (!NAME_RE.test(name))
    errors.push(`${label}: name "${name}" must be lowercase alphanumeric/hyphens`);
  if (name.length > 64) errors.push(`${label}: name exceeds 64 chars`);
  if (description && description.length > 1024)
    errors.push(`${label}: description exceeds 1024 chars`);
}

if (dirs.length === 0) errors.push("no skills found under skills/");

if (errors.length > 0) {
  for (const e of errors) console.error(`✗ ${e}`);
  console.error(`\nValidation failed with ${errors.length} error(s).`);
  process.exit(1);
}

console.log(`✓ ${dirs.length} skill(s) validated successfully.`);
