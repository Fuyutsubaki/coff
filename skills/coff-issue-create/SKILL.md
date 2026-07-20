---
name: coff-issue-create
description: Scaffold a new issue under `issue/`.
license: MIT
---

## Procedure

1. Read `.claude/skills/coff-detail-issue/SKILL.md` to learn the location, naming, template, and quality bar.
2. Prepare the current month's directory with `mkdir -p "issue/$(date +%Y/%m)"`.
3. Write only the problem space. From the user's request, articulate タイトル / 背景・目的 / 現状. Write the body following the coff-japanese-tech-writing skill.
4. Examine the problem's validity against detail's four angles. Also check whether it contains multiple problems whose adoption and completion can be judged independently; if so, propose filing them as separate issues (1 issue = 1 intent, per detail's Purpose section). If the user explicitly instructs to bundle them, follow it and record that fact and the reason under 「人間が決めた判断」. Leave doubts, alternative framings, and rejected scopes under "リスク・未解決". Don't do deep code investigation (reading the minimum to confirm the problem exists is fine). Only when the problem's frame (type, purpose, success criteria) can't be determined, ask lightly. Questioning discipline: one question at a time, attach a recommended answer to each, and investigate what the code can answer yourself instead of asking. No relentless full-breadth interview; stop once the frame is settled.
5. Don't write the solution space (要約 / 変更方針 / 実装詳細 / 検証). Leave placeholders such as "解決空間。polish で詰める".
6. Pick a filename per the naming rule and create `issue/<yyyy>/<mm>/<name>.md`. Add a `status: open` frontmatter at the top of the file (per detail's status spec).
7. Report the created path. To go on and work out the solution, point to the coff-issue-polish skill.

## Exit bar

- The problem is correctly framed. The solution is left to polish.
<!--{"src":".coff/src/coff-issue-create.skill.md","md5":"f3ad597a0cd1caee1d161efa1b6434c8"} -->
