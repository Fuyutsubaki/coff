---
name: coff-dullmify
description: Split a skill source into a deterministic Perl workflow and a thin SKILL.md. Specify the source and the output directory as `<source>.skill.md -o <dir>`.
license: MIT
allowed-tools: Bash(perl ${CLAUDE_SKILL_DIR}/scripts/workflow.pl *)
---

## Run the workflow

Run `perl ${CLAUDE_SKILL_DIR}/scripts/workflow.pl start $ARGUMENTS` and read the JSON response.

When the response has `ask`, compose the answer according to `topic`, and pass only the answer on standard input to `perl ${CLAUDE_SKILL_DIR}/scripts/workflow.pl resume <run> <index>`.
Pass the answer verbatim with a single-quoted heredoc.
Repeat until `done: true`.

## Judgment per topic

### `workflow`

Read `source` and return, in Perl, only `sub workflow` and the helper functions specific to that skill.
When `existing` is not empty, keep its structure and limit the answer to the necessary changes.
Do not include Markdown fences, a shebang, `use` declarations, `run_workflow`, or a generated footer.

Put side effects in argument-free `step { ... }` blocks and express failures with `die`.
Express both LLM judgments and questions for the user with `llm(topic, input)`.
State in each topic's criteria whether it is a question for the user.
Do not use clocks or randomness, and sort hash keys before processing.
Do not wrap an effect in `eval {}`.

Use only syntax that runs on Perl 5.30 and core modules.
`require` any additional core module inside the helper function and call it by its fully qualified name.
Write at least one line of Japanese comment stating the purpose immediately before each helper function.
The `use` declarations and the `run_workflow` call belong to the templates, so do not write them in the answer.

### `topics`

From `source`, return in Markdown the judgment criteria for each topic the workflow uses.
For each topic, write the input, the answer format, and the judgment criteria.
Instruct that questions for the user are presented with AskUserQuestion.
Do not include frontmatter, the common request-response procedure, the completion report, or Markdown fences.
Write tersely in the same language as the source.

## Completion report

When the response becomes `done: true`, present `report`.
Do not present an empty report.
<!--{"src":".coff/src/coff-dullmify.skill.md","md5":"1d1171a459de54721268b1611cedce5e"} -->
