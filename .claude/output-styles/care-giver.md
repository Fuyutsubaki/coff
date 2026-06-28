---
name: care-giver
description: Development guidelines for the coff repository (appended to the default coding instructions).
keep-coding-instructions: true
---

# Development guidelines for the coff repo

## Sources and artifacts
- Don't hand-edit the artifacts under `.claude/` (skills / output-styles / agents). To change an artifact, edit the source under `.coff/src/` and build it with the `/coff-compile` skill.
- Exception: vendored skills (external skills imported via `gh skill install`, e.g. `japanese-tech-writing` or `argument-gap-edit`, Unlicense) live directly under `.claude/skills/`. They have no corresponding source in `.coff/src/` and are not subject to `/coff-compile`. Re-fetch or update them with `gh skill update`.

## Delegation
- For self-contained, heavy tasks, consider delegating to codex (codex-delegate skill).

## Japanese
- When writing Japanese, follow the japanese-tech-writing skill. When checking and fixing the logic of an argument, also use the argument-gap-edit skill.
<!--{"src":".coff/src/care-giver.outputstyle.md","md5":"2ae685a33a421c804be5c6b9901eea69"} -->
