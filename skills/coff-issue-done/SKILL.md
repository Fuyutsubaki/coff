---
name: coff-issue-done
description: Mark an issue under `issue/` as done. Verify the acceptance criteria are met and the record is consistent with the current state, then update its frontmatter `status` to `done`.
license: MIT
---

## Procedure

1. Learn the status spec from `.claude/skills/coff-detail-issue/SKILL.md`.
2. Read the target issue file passed as the argument.
3. Completion check (lightweight gate). If it fails, do not set `done`; report the reason and hand it back.
   - Confirm every checkbox in the 「検証」 section (「受け入れ条件」 in the old template) is checked (filling the boxes is the implementer's responsibility, per detail's rules). If any is unchecked, hold and list those items.
   - Confirm the body (現状・変更方針・実装詳細) has no obvious mismatch with the actual repository. If it does, hold and point it out. Do not rewrite the body (a human decides whether to fix the body or move the point to risks).
   - An issue with neither a 「検証」 nor a 「受け入れ条件」 section, or an empty one, passes the check with a warning to that effect.
4. Once the check passes, branch on the presence of frontmatter and `status` to set `done`.
   - If frontmatter exists and has `status`, rewrite its value to `done`.
   - If frontmatter exists without `status`, add `status: done` to the frontmatter.
   - If there is no frontmatter, insert `---` / `status: done` / `---` at the top of the file (the body follows unchanged).
5. Never change the body (from `#` on).
6. Report the updated path and the new `status`.

## Scope

- Updates go in the `done` direction only. Reverting (`done` → `open`) is done by hand-editing.
<!--{"src":".coff/src/coff-issue-done.skill.md","md5":"5f0a2f8e0531a0a1de083916edb13fbe"} -->
