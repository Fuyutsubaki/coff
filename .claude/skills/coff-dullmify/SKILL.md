---
name: coff-dullmify
description: Split `.coff/src/<name>.skill.md` into a deterministic Perl workflow and a thin SKILL.md. Accept `<name> [--out <dir>]`; the default output is `.claude/skills/<name>/`.
license: MIT
allowed-tools: Bash(perl ${CLAUDE_SKILL_DIR}/scripts/run.pl *)
---

## Run the workflow

Run `perl ${CLAUDE_SKILL_DIR}/scripts/run.pl --workflow dullmify.pl start $ARGUMENTS` and read the JSON response.

When the response contains `ask`, prepare an answer according to `kind` and `topic`. Pass only the answer through standard input to `perl ${CLAUDE_SKILL_DIR}/scripts/run.pl --workflow dullmify.pl resume <run> <index>`.
Pass the answer unchanged with a single-quoted heredoc.
Repeat until `done: true`.

If conversational context is lost, retrieve the pending question with `--workflow dullmify.pl status <run>`.
Use `--workflow dullmify.pl cancel <run>` to end a run and `--workflow dullmify.pl gc` to remove runs older than seven days.

## Topic `workflow`

Read `source` and return only `sub workflow` and helper functions specific to that skill in Perl.
When `existing` contains a `workflow.pl`, limit the response to necessary changes.
Do not include Markdown fences, a shebang, `use` declarations, a `run_workflow` call, or a generated footer.

Put side effects in argument-free `step { ... }` blocks and express failures with `die`.
Use `attempt { ... }` to turn per-target failures into reports while continuing.
Pass only a topic and input to `llm` and `user`.
Do not use clocks or randomness. Sort hash keys before iterating.
Do not wrap effects in a raw `eval`.

Use syntax supported by Perl 5.30 and core modules only.
`run.pl` loads `Digest::MD5`, `Encode`, `File::Basename`, `File::Find`, `File::Path`, `File::Spec`, `JSON::PP`, and `llm`, `user`, `step`, `attempt`, and `publish_files` from `Coff::Workflow`.
The assembler adds `use utf8`; do not include it in the answer.

## Topic `topics`

From `source`, return concise Markdown criteria for each `llm` and `user` topic used by the workflow.
Describe only the input, answer format, and judgment criteria.
Do not include frontmatter, the common request-response procedure, the completion report, or Markdown fences.
Use the same language as the source.

## Completion report

When the response becomes `done: true`, present `report`.
Do not present an empty report.
<!--{"src":".coff/src/coff-dullmify.skill.md","md5":"3e5d5ed91be60508073f8fd030563030"} -->
