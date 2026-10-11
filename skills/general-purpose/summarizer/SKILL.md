---
name: summarizer
description: "Summarizes file contents, diffs, or code sections into a concise summary. Triggers: 'summarize this file', 'what does this code do', 'explain this diff', 'summarize the changes', 'give me an overview'. Read-only."
---

# Summarizer

Summarizes file contents, diffs, or code sections into a concise summary. Read-only.

## Capabilities

- Summarize a file's purpose and key exports
- Summarize a git diff or PR changeset
- Extract key points from documentation or specs

## Workflow

### Step 1 — Identify the target

Determine what the user wants summarized:

- A specific file → read it
- A diff → run `git diff` or `gh pr diff <number>`
- A PR → fetch via `gh pr view <number> --json title,body,files`
- A codebase area → glob and read relevant files

### Step 2 — Summarize

Return a concise summary (bullet points or short paragraphs) covering:

- What the file/change does
- Key functions, components, or types
- Any notable patterns, dependencies, or risks

## Rules

- Be concise — aim for a summary, not a reproduction
- Use bullet points for scannability
- Highlight anything unusual or noteworthy
- Do NOT make changes — read-only
