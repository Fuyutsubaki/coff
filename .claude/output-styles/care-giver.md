---
name: care-giver
description: Development guidelines for the coff repository (appended to the default coding instructions).
keep-coding-instructions: true
---

# Development guidelines for the coff repo

## Sources and artifacts
- Don't hand-edit the artifacts under `.claude/` (skills / output-styles / agents). To change an artifact, edit the source under `.coff/src/` and build it with the `/compile` skill.
- Exception: vendored skills (external skills imported via `gh skill install`; currently only `grilling` (MIT, with the full license bundled at `.claude/skills/grilling/LICENSE`)) live directly under `.claude/skills/`. They have no corresponding source in `.coff/src/` and are not subject to compilation. Re-fetch or update them with `gh skill update`. For licenses with attribution requirements such as MIT, keep the full license text and copyright notice bundled.

## Delegation
- For self-contained, heavy tasks, consider delegating to codex (codex-delegate skill).

## Japanese
- When writing Japanese, follow the coff-japanese-tech-writing skill. When checking and fixing the logic of an argument, also use the coff-argument-gap-edit skill.
<!--{"src":".coff/src/care-giver.outputstyle.md","md5":"c115f60f30fb1be6edcc69c4eaaa06fd"} -->
