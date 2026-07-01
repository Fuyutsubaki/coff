---
name: coff-issue-done
description: Mark an issue under `issue/` as done by updating its frontmatter `status` to `done`.
---

## Procedure

1. Learn the status spec from `.claude/skills/coff-detail-issue/SKILL.md`.
2. Read the target issue file passed as the argument.
3. Set `status` to `done`, branching on whether frontmatter and `status` exist.
   - If frontmatter exists and has `status`, rewrite its value to `done`.
   - If frontmatter exists but has no `status`, add `status: done` to the frontmatter.
   - If there is no frontmatter, insert `---` / `status: done` / `---` at the top of the file (leave the body following as-is).
4. Do not change the body (everything from `#` onward) at all.
5. Report the updated path and the new `status`.

## Scope

- Updates only in the `done` direction. Reverting (`done` → `open`) is done by hand-editing.
<!--{"src":".coff/src/coff-issue-done.skill.md","md5":"b65137c9b6fc1f35a27e5af4fad2b2d9"} -->
