---
name: coff-compile
description: Build coff sources in `.coff/src/` into runtime artifacts under `.claude/`. Maps `.skill.md` to skills, `.outputstyle.md` to output styles, and `.agent.md` to agents. With no arguments, build all sources. Accept a `<name>`, `--lint-only`, `--force`, `--out`, `--ref`, and `--agent`.
license: MIT
allowed-tools: Bash(perl ${CLAUDE_SKILL_DIR}/scripts/run.pl *)
---

## Run the workflow

Run `perl ${CLAUDE_SKILL_DIR}/scripts/run.pl start $ARGUMENTS` and read the JSON response.

When the response contains `ask`, prepare an answer according to `kind` and `topic`. Pass only the answer through standard input to `perl ${CLAUDE_SKILL_DIR}/scripts/run.pl resume <run> <index>`.
Pass the answer unchanged with a single-quoted heredoc.
Repeat until `done: true`.

If conversational context is lost, retrieve the pending question with `status <run>`.
Use `cancel <run>` to end a run and `gc` to remove runs older than seven days.

## Topic criteria

### `lint-candidates` (`kind: llm`)

Read `path` and `content`. Return lint candidates as a JSON array.
Represent each candidate as `{start, end, replacement, label}` with ascending, non-overlapping line ranges.
Do not add explanations or Markdown fences. Return `[]` when there are no candidates.

In the body, identify WHY text, reader-facing notices, repetition, contrapositives, excessive examples, and repeated structure that can be removed without preventing execution.
Exclude comments, frontmatter, fenced code blocks, and inline code.
For frontmatter `description`, identify content other than WHAT and invocation details.
Prefix `label` with `[推奨]` for comment conversion and meaning-preserving deduplication, or `[要判断]` when judgment is required.
Include the lines, quotation, method, recommendation, and resulting preview in `label`.

### `lint-approval` (`kind: user`)

Present `path` and `candidates` together with AskUserQuestion using `multiSelect=true`.
If there are too many candidates, split first by file and then by section.
Return only a JSON array containing the zero-based `index` of each approved candidate. Do not add explanations or Markdown fences.

### `compile-confirmation` (`kind: user`)

Present `message` with AskUserQuestion and ask whether to continue compilation.
Return only `yes` for approval or `no` for rejection.

### `dullmify` (`kind: llm`)

Use `name` and `out` to run `/coff-dullmify <name> --out <out>`.
Return only `ok` when it finishes successfully and writes all four artifacts.
On failure, return only the reason. Do not include `source` or staging contents in the answer.

### `translate` (`kind: llm`)

Translate the complete `content` document into concise English and return only the document.
Translate prose, headings, list items, and the frontmatter `description`.
Preserve quoted literals, identifiers, paths, CLI flags, regular expressions, command arguments, code, frontmatter keys and `name`, proper nouns, UI strings, and error messages.
Preserve uncertain text. Do not wrap the document in a Markdown fence.

## Completion report

When the response becomes `done: true`, present `report`.
Do not present an empty report.
<!--{"src":".coff/src/coff-compile.skill.md","md5":"0cefd543890cac41e72374fc14ce522b"} -->
