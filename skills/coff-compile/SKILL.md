---
name: coff-compile
description: Build coff sources (`.coff/src/`) into runtime artifacts under `.claude/`. `.skill.md` → skills, `.outputstyle.md` → output-styles, `.agent.md` → agents. No args = all; `<name>` for individual; `--lint-only` for pre-check only; `--force` to rebuild even unchanged sources. `--out` / `--ref` / `--agent` add destination override, reference stubs, and per-agent output.
license: MIT
allowed-tools: Bash(perl ${CLAUDE_SKILL_DIR}/scripts/coff-compile.pl *)
---

## Run the workflow

Run `perl ${CLAUDE_SKILL_DIR}/scripts/coff-compile.pl start $ARGUMENTS` and read the JSON response.

When the response has `ask`, answer according to its `kind` and `topic`, and pass only the answer on standard input to `perl ${CLAUDE_SKILL_DIR}/scripts/coff-compile.pl resume <run> <index>`.
Pass the answer verbatim with a single-quoted heredoc.
Repeat until the response has `done: true`.

After context loss, retrieve the unanswered question with `status <run>`. End a run with `cancel <run>`, and remove runs older than seven days with `gc`.

## LLM topics

For `lint-candidates`, inspect the supplied source conservatively.
Return a JSON array whose entries have `start`, `end`, `replacement`, and `label`.
Line numbers are one-based and inclusive, ranges are ascending and non-overlapping, and `[]` means no candidates.
Include in `label` the affected lines, the quotation, the action, the recommendation (`[推奨]` or `[要判断]`), and the resulting preview.

Propose wrapping design rationale and reader-facing notes in HTML comments, deleting rephrased repetition and duplicated condition explanations, and rewriting duplicated structure and redundant examples concisely.
Exclude existing HTML comments, frontmatter, fenced code, and inline code.
Check frontmatter `description` separately, proposing to shorten anything beyond what it does and how the user invokes it.
Propose only what the executing LLM can still complete the procedure without once it is removed from the artifact.

For `dullmify-perl`, return a complete Perl program that begins with `#!/usr/bin/env perl`, without a Markdown fence or a footer.
Preserve the supplied existing program and change only what the source requires.
Use Perl 5.30 syntax and core modules, declare `use utf8`, locate `lib/` with `FindBin`, and use `run_workflow`, `llm`, `user`, `step`, and `publish_files` from `Coff::Workflow`.
Keep every side effect inside `step`, use no clocks or randomness, iterate hash keys in sorted order, and never wrap an effect call in `eval`.
Use `llm` only for textual judgment and code generation, and `user` only for questions that need the user's decision.

For `dullmify-skill`, return only the thin skill body in the source language, without frontmatter, a footer, or fenced code.
Keep the start/resume loop, the judgment criteria the LLM needs per topic, the handling of user questions, the final report, and `status` / `cancel` / `gc`.
Do not write deterministic control procedures.

For `translate`, return the whole supplied document in concise English.
Translate prose, headings, lists, and the frontmatter `description`.
Preserve byte-for-byte quoted literals used for matching or verbatim output, identifiers, paths, flags, regular expressions, command arguments, fenced and inline code, frontmatter keys and identifier values, proper nouns, UI strings, and error messages.
When uncertain, keep the original.

## User topics

For `lint-approval`, call AskUserQuestion once with `multiSelect=true` and the supplied candidate labels.
Return the zero-based indexes of the selected candidates as a JSON array.

For `compile-confirmation`, show the supplied message with AskUserQuestion and return `yes` only when approved, otherwise `no`.

## Completion

When the response has `done: true`, present each string in `report`.
Do not report an empty list.
<!--{"src":".coff/src/coff-compile.skill.md","md5":"1c20282ca32a5f732b2fa9189e6acdd4"} -->
