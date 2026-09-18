---
name: coff-dullmify
description: Split a skill source into a deterministic Perl workflow and a thin SKILL.md. Specify the source and output directory as `<source>.skill.md -o <dir>`.
license: MIT
allowed-tools: Bash(perl ${CLAUDE_SKILL_DIR}/scripts/run.pl *)
---

## Run the workflow

Run `perl ${CLAUDE_SKILL_DIR}/scripts/run.pl start $ARGUMENTS` and read the JSON response.

When the response contains `ask`, compose an answer according to `topic` and pass only the answer on standard input to `perl ${CLAUDE_SKILL_DIR}/scripts/run.pl resume <run> <index>`.
Pass the answer verbatim with a single-quoted heredoc.
Repeat until `done: true`.

## Judgment by topic

### topic `workflow`

Return only `sub workflow` and skill-specific helper functions derived from `source`.
When `existing` is nonempty, preserve its structure and make only necessary changes.
Do not include Markdown fences, a shebang, `use` declarations, `run_workflow`, or a generated footer.
Put side effects in `step { ... }` and express failures with `die`.
Express LLM judgments and user questions with `llm(topic, input)`.
Use only Perl 5.30 syntax and core modules, and write a preceding Japanese comment that states the purpose of every helper function.

### topic `topics`

Return only the Markdown judgment criteria for each topic used by the workflow, derived from `source`.
For each topic, state its input, answer format, and judgment criteria.
Present user questions with AskUserQuestion.
Do not include frontmatter, the common exchange procedure, completion reporting, or Markdown fences.

## Completion report

When the response becomes `done: true`, present `report`.
Do not present an empty report.
<!--{"src":".coff/src/coff-dullmify.skill.md","md5":"a4bb79947fef42785895b5fd66f6ac2c"} -->
