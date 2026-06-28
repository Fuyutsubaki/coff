---
name: codex-delegate
description: Delegate self-contained implementation, investigation, or bug-fix tasks to the codex@openai-codex plugin.
---

## When to delegate

- Self-contained implementation / investigation / bug-fix (run in a separate process without using the main context)
- Don't delegate: small edits, or work that needs tight back-and-forth with the user

## Procedure

1. Write a brief: goal / constraints / target files / acceptance criteria.
   - codex also explores on its own in a separate process, so a light brief is fine when that suffices.
   - When you want to pass repo-specific assumptions or key points, investigate the relevant files/structure/dependencies at this step and fold them into the brief.
2. Short task → `/codex:rescue <brief>` (sync). Long / parallel → `/codex:rescue --background <brief>`.
3. Progress: `/codex:status`.
4. Retrieve: `/codex:result <task-id>` → review and integrate.
5. Resume / cancel: `--resume <task-id>` / `/codex:cancel`.

## Notes

- On first use only, run `/codex:setup` to verify codex authentication.
<!--{"src":".coff/src/codex-delegate.skill.md","md5":"31add1f0a6c93b47c47d81ffefd0fa52"} -->
