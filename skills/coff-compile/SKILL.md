---
name: coff-compile
description: Build coff sources (`.coff/src/`) into runtime artifacts under `.claude/`. `.skill.md` → skills, `.outputstyle.md` → output-styles, `.agent.md` → agents. No args = all; `<name>` for individual; `--lint-only` for pre-check only; `--force` to rebuild even unchanged sources. `--out` / `--ref` / `--agent` add destination override, reference stubs, and per-agent output.
license: MIT
allowed-tools: Bash(perl ${CLAUDE_SKILL_DIR}/scripts/coff-compile.pl *)
---

## Run the workflow

Run `perl ${CLAUDE_SKILL_DIR}/scripts/coff-compile.pl start $ARGUMENTS` and read its JSON response.

For a response with `ask`, answer according to its `kind` and `topic`, then pass only the answer on standard input to `perl ${CLAUDE_SKILL_DIR}/scripts/coff-compile.pl resume <run> <index>`.
Use a single-quoted heredoc so the answer is passed verbatim.
Repeat until the response has `done: true`.

Use `status <run>` to retrieve the unanswered question after context loss, `cancel <run>` to terminate a run, and `gc` to remove runs older than seven days.

## LLM topics

For `lint-candidates`, inspect the supplied source conservatively.
Return a JSON array whose entries contain `start`, `end`, `replacement`, and `label`.
Use one-based inclusive line numbers, ascending non-overlapping ranges, and `[]` when there are no candidates.
The label must include the affected lines, quotation, action, recommendation (`[推奨]` or `[要判断]`), and resulting preview.

Flag design rationale and reader-facing notes for HTML-comment wrapping, repeated wording and redundant condition restatements for deletion, and duplicated structure or excessive examples for concise replacement.
Exclude existing HTML comments, frontmatter, fenced code, and inline code.
Check frontmatter `description` separately: keep only what the artifact does and how or when the user invokes it.
Only propose a change when removing it from the compiled artifact still leaves enough instruction to complete the task.

For `dullmify-perl`, return a complete Perl program beginning with `#!/usr/bin/env perl`, without a Markdown fence or generated footer.
Preserve the supplied existing program and change only what the source requires.
Use Perl 5.30 syntax and core modules, locate `lib/` with `FindBin`, and use `Coff::Workflow` exports `run_workflow`, `llm`, `user`, `step`, and `publish_files`.
Keep all side effects inside `step`, avoid clocks and randomness, iterate hash keys in sorted order, and never wrap an effect call in `eval`.
Use `llm` only for textual judgment or code generation and `user` only for questions that require the user's decision.

For `dullmify-skill`, return only the thin skill body in the source language, without frontmatter, a footer, or fenced code.
Keep the start/resume loop, the topic-specific judgment rules the LLM needs, user-question handling, terminal reporting, and the `status`, `cancel`, and `gc` commands.
Do not restate deterministic workflow control.

For `translate`, return the complete supplied document in concise English.
Translate prose, headings, lists, and the frontmatter `description`.
Preserve quoted literals used for matching or verbatim output, identifiers, paths, flags, regular expressions, command arguments, fenced and inline code, frontmatter keys and identifier values, proper nouns, UI strings, and error messages byte-for-byte.
When uncertain, preserve the original.

## User topics

For `lint-approval`, call AskUserQuestion once with `multiSelect=true` and the supplied candidate labels.
Return a JSON array containing the zero-based indexes of the selected candidates.

For `compile-confirmation`, show the supplied message with AskUserQuestion and return `yes` only when the user approves; otherwise return `no`.

## Completion

When the response has `done: true`, present each string in `report`.
Do not report an empty list.
<!--{"src":".coff/src/coff-compile.skill.md","md5":"b54b85c9c38f880d34fca5a109cf481e"} -->
