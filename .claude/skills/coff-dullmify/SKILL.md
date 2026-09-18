---
name: coff-dullmify
description: Split a skill source into a deterministic Perl workflow and a thin SKILL.md. Specify the source and the output directory with `<source>.skill.md -o <dir>`. There are no defaults.
license: MIT
allowed-tools: Bash(perl ${CLAUDE_SKILL_DIR}/scripts/run.pl *)
---

## Run the workflow

Run `perl ${CLAUDE_SKILL_DIR}/scripts/run.pl --workflow dullmify.pl start $ARGUMENTS` and read the JSON response.

When the response has `ask`, compose the answer according to `kind` and `topic`, and pass only the answer on standard input to `perl ${CLAUDE_SKILL_DIR}/scripts/run.pl --workflow dullmify.pl resume <run> <index>`.
Pass the answer verbatim with a single-quoted heredoc.
Repeat until `done: true`.

After losing conversation context, retrieve the unanswered question with `--workflow dullmify.pl status <run>`.
Use `--workflow dullmify.pl cancel <run>` to end a run and `--workflow dullmify.pl gc` to remove runs older than seven days.

## Topic `workflow`

Read `source` and return, in Perl, only `sub workflow` and the helper functions specific to that skill.
When `existing` holds an existing `workflow.pl` (the one placed in the output directory), limit the answer to the necessary changes.
Do not include Markdown fences, a shebang, `use` declarations, a `run_workflow` call, or a generated footer.

Put side effects in argument-free `step { ... }` blocks and express failures with `die`.
Use `attempt { ... }` to turn per-target failures into reports that let the run continue.
Pass only a topic and an input to `llm` and `user`.
Do not use clocks or randomness, and sort hash keys before iterating.
Do not wrap an effect in a raw `eval`.

Use only syntax that runs on Perl 5.30 and core modules.
Use `Digest::MD5`, `Encode`, `File::Basename`, `File::Find`, `File::Path`, `File::Spec`, and `JSON::PP`, which `run.pl` loads, and `llm`, `user`, `step`, `attempt`, and `publish_files` from `Coff::Workflow`.
`use utf8` is added at generation time, so do not write it in the answer.

## Topic `topics`

From `source`, return in Markdown the judgment criteria for each `llm` and `user` topic the workflow uses.
Write only the inputs included in the question, the answer format, and the judgment criteria.
Do not include frontmatter, the common request-response procedure, the completion report, or Markdown fences.
Write tersely in the same language as the source.

## Completion report

When the response becomes `done: true`, present `report`.
Do not present an empty report.
<!--{"src":".coff/src/coff-dullmify.skill.md","md5":"2510a9cf99c73128fcfb531491fe940b"} -->
