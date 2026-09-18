---
name: coff-compile
description: Build coff sources (`.coff/src/`) into runtime artifacts under `.claude/`. `.skill.md` → skills, `.outputstyle.md` → output-styles, `.agent.md` → agents. No args = all; `<name>` for individual; `--lint-only` for pre-check only; `--force` to rebuild even unchanged sources. `--out` / `--ref` / `--agent` add destination override, reference stubs, and per-agent output.
license: MIT
allowed-tools: Bash(perl ${CLAUDE_SKILL_DIR}/scripts/run.pl *)
---

## Run the workflow

Run `perl ${CLAUDE_SKILL_DIR}/scripts/run.pl start $ARGUMENTS` and read the JSON response.

When the response has `ask`, compose the answer according to `kind` and `topic`, and pass only the answer on standard input to `perl ${CLAUDE_SKILL_DIR}/scripts/run.pl resume <run> <index>`.
Pass the answer verbatim with a single-quoted heredoc.
Repeat until `done: true`.

After losing conversation context, retrieve the unanswered question with `status <run>`.
Use `cancel <run>` to end a run and `gc` to remove runs older than seven days.

## Judgment per topic

### `lint-candidates` (`kind: llm`)

Inspect the source given by `path` and `content` conservatively.
Return a JSON array whose entries have `start`, `end`, `replacement`, and `label`. Line numbers are one-based and inclusive, and ranges are ascending and non-overlapping. Return `[]` when there are no candidates.
Include in `label` the affected lines, the quotation, the action, the recommendation (`[推奨]` or `[要判断]`), and the resulting preview.

Propose wrapping design rationale and reader-facing notes in HTML comments, deleting rephrased repetition and duplicated condition explanations, and rewriting duplicated structure and redundant examples concisely.
Exclude existing HTML comments, frontmatter, fenced code, and inline code.
Check the frontmatter `description` separately, proposing to shorten anything beyond what it does and how the user invokes it.
Propose only what the executing LLM can still complete the procedure without once the sentence is removed from the artifact.

### `lint-approval` (`kind: user`)

Call AskUserQuestion once with `multiSelect=true` and the labels in `candidates`.
Return the zero-based indexes of the selected candidates as a JSON array.

### `compile-confirmation` (`kind: user`)

Show `message` with AskUserQuestion and return `yes` only when approved, otherwise `no`.

### `dullmify` (`kind: llm`)

Use `source` and `out` to run `/coff-dullmify <source> -o <out>`.
Return only `ok` when it finishes successfully with all four artifacts written. On failure, return only the reason. Do not include the staging contents in the answer.

### `translate` (`kind: llm`)

Return the whole document in `content` in concise English.
Translate prose, headings, lists, and the frontmatter `description`.
Preserve byte-for-byte quoted literals used for matching or verbatim output, identifiers, paths, flags, regular expressions, command arguments, fenced and inline code, frontmatter keys and identifier values, proper nouns, UI strings, and error messages.
When uncertain, keep the original.

## Completion report

When the response becomes `done: true`, present `report`.
Do not present an empty report.
<!--{"src":".coff/src/coff-compile.skill.md","md5":"783915131dbea57c086fd5535ba78d53"} -->
