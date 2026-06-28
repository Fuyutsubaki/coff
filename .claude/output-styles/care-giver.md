---
name: care-giver
description: Development guidelines for the coff repository (appended to the default coding instructions).
keep-coding-instructions: true
---

# Development guidelines for the coff repo

## Sources and artifacts
- Don't hand-edit the artifacts under `.claude/` (skills / output-styles / agents). To make changes, edit the sources under `.coff/src/` and use the `/coff-compile` skill.
- Exception: vendored skills (external skills imported via `gh skill install`, e.g. `japanese-tech-writing` / `argument-gap-edit`, Unlicense) live directly under `.claude/skills/`. They have no source in `.coff/src/` and are not subject to `/coff-compile`. Re-fetch / update them with `gh skill update`.

## Delegation
- For self-contained, heavy tasks, consider delegating to codex (codex-delegate skill).

## Japanese
- When writing Japanese, follow the japanese-tech-writing skill. When checking or editing the logic of an argument, also use the argument-gap-edit skill.
<!--{"src":".coff/src/care-giver.outputstyle.md","md5":"20cd7153dbecc0c39d6b30fb7a1fa93d"} -->
