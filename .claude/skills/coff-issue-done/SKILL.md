---
name: coff-issue-done
description: Mark an issue under `issue/` as done. Verify the acceptance criteria are met and the record is consistent with the current state, then update its frontmatter `status` to `done`.
---

## Procedure

1. Learn the status spec from `.claude/skills/coff-detail-issue/SKILL.md`.
2. Read the target issue file passed as the argument.
3. Completion check (lightweight gate). If it doesn't pass, don't set `done`; report the reason and hand it back.
   - Confirm every item in the checklist of the 「検証」 section (in the old template, the 「受け入れ条件」 section) is ticked (ticking the boxes is the implementer's responsibility, per detail's rule). If any is unticked, hold and list those items.
   - Confirm there's no clear discrepancy between the body (現状 / 変更方針 / 実装詳細) and the actual repository. If there is, hold and point it out. Don't rewrite the body (resolving the contradiction is a human call — fix the body, or move it to リスク).
   - If the issue has neither a 「検証」 nor a 「受け入れ条件」 section, or it is empty, warn about it and let the check pass.
4. Once the check passes, set `status` to `done`, branching on whether frontmatter and `status` exist.
   - If frontmatter exists and has `status`, rewrite its value to `done`.
   - If frontmatter exists but has no `status`, add `status: done` to the frontmatter.
   - If there is no frontmatter, insert `---` / `status: done` / `---` at the top of the file (leave the body following as-is).
5. Do not change the body (everything from `#` onward) at all.
6. Report the updated path and the new `status`.

## Scope

- Updates only in the `done` direction. Reverting (`done` → `open`) is done by hand-editing.
<!--{"src":".coff/src/coff-issue-done.skill.md","md5":"f08eb66af4491c9c239d02ea53b2e6da"} -->
