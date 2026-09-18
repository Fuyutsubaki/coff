---
name: coff-compile
description: Build coff sources (`.coff/src/`) into runtime artifacts under `.claude/`. `.skill.md` → skills, `.outputstyle.md` → output-styles, `.agent.md` → agents. No arguments builds all sources; `<name>` builds one; `--lint-only` runs only the pre-check; `--force` rebuilds unchanged sources. `--out`, `--ref`, and `--agent` select alternate outputs, reference stubs, and agent-specific outputs.
license: MIT
allowed-tools: Bash(perl ${CLAUDE_SKILL_DIR}/scripts/run.pl *)
---

## Run the workflow

Run `perl ${CLAUDE_SKILL_DIR}/scripts/run.pl start $ARGUMENTS` and read the JSON response.

When the response contains `ask`, compose an answer according to `topic` and pass only the answer on standard input to `perl ${CLAUDE_SKILL_DIR}/scripts/run.pl resume <run> <index>`.
Pass the answer verbatim with a single-quoted heredoc.
Repeat until `done: true`.

## Judgment by topic

### topic `lint-candidates`

Inspect the source in `path` and `content` conservatively.
Return candidates as a JSON array of `{start, end, replacement, label}` objects.
Use one-based inclusive line numbers, ascending non-overlapping ranges, and return `[]` when there are no candidates.
Include the affected lines, quotation, action, `[推奨]` or `[要判断]`, and resulting preview in `label`.
Exclude existing HTML comments, frontmatter, fenced code, and inline code.
Propose only changes that still let the executing LLM complete the procedure.

### topic `lint-approval`

Present the labels in `candidates` once with AskUserQuestion and `multiSelect=true`.
Return the zero-based indexes of the selected candidates as a JSON array.

### topic `compile-confirmation`

Present `message` with AskUserQuestion.
Return `yes` only when approved; otherwise return `no`.

### topic `dullmify`

Use `source` and `out` to run `/coff-dullmify <source> -o <out>`.
Return only `ok` after all four files are written successfully; otherwise return only the reason.
Do not include staging contents in the answer.

### topic `translate`

Return the whole document in `content` in concise English.
Translate prose, headings, lists, and the frontmatter `description`.
Preserve byte-for-byte quoted literals used for matching or verbatim output, identifiers, paths, flags, regular expressions, command arguments, fenced and inline code, frontmatter keys and identifier values, proper nouns, UI strings, and error messages.
When uncertain, preserve the original.

## Completion report

When the response becomes `done: true`, present `report`.
Do not present an empty report.
<!--{"src":".coff/src/coff-compile.skill.md","md5":"86343ce6d7e505aafaf5cc1dfe27fafe"} -->
