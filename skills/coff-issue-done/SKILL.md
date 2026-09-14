---
name: coff-issue-done
description: Mark an issue under `issue/` as done.
license: MIT
---

## Procedure

1. Get the status spec and done's exit bar from `.claude/skills/coff-detail-issue/SKILL.md`.
2. Read the target issue file passed as the argument.
3. Completion verification (lightweight gate). If it fails, do not set `done`; report the reason and bounce it back.
   - Confirm every item in the 「完了条件」 section's checklist (「検証」 or 「受け入れ条件」 in the old templates) is ticked (per detail's rules). If any is unticked, hold and list those items.
   - If the 「未決」 section still has items, hold and list them. Point out that settled ones go under 「決めたこと」 and 設計方針, and unsettled ones go to a separate issue. The old template's 「リスク・未解決」 section is not a hold criterion; if it still has items, only warn.
   - Check for obvious discrepancies between the body (現状 / 設計方針 / 実装メモ) and the actual repository. If any, hold and point them out (bringing the body in line with what was built is the implementer's job, per detail's quality bar).
   - If the issue has none of 「完了条件」 / 「検証」 / 「受け入れ条件」, or the section is empty, warn about it and pass the verification.
   - If the issue involves an implementation and a multi-perspective review appears not to have been done, point to the coff-review-diff-code skill (the pointer does not affect the gate's verdict).
4. Once verification passes, set `done` depending on whether frontmatter and `status` exist.
   - If frontmatter exists and has `status`, rewrite its value to `done`.
   - If frontmatter exists but has no `status`, add `status: done` to the frontmatter.
   - If there is no frontmatter, insert `---` / `status: done` / `---` at the top of the file (the body follows as is).
5. Do not change the body (from `#` onward) at all.
6. Report the updated path and the new `status`.

## Scope

- Updates go in the `done` direction only. Reverting (`done` → `open`) is done by hand.
<!--{"src":".coff/src/coff-issue-done.skill.md","md5":"c2f7298ba80cd0c723c54fabec961b2f"} -->
