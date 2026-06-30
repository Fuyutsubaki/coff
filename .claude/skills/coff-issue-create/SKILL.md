---
name: coff-issue-create
description: Scaffold a new issue under `issue/`.
---

## Procedure

1. Read `.claude/skills/coff-detail-issue/SKILL.md` to learn the location, naming, template, and quality bar.
2. If the `issue/` directory doesn't exist, create it with `mkdir -p issue`.
3. Write only the problem space. From the user's request, articulate タイトル / 背景・目的 / 現状. Write the body following the japanese-tech-writing skill.
4. Examine the problem's validity (detail's four angles: is it actually worth solving / is it already solved / is the question framed correctly / is there another framing). Leave doubts, alternative framings, and rejected scopes under "リスク・未解決". Don't do deep code investigation (reading the minimum to confirm the problem exists is fine). Only when the problem's frame (type, purpose, success criteria) can't be determined, ask lightly using the grilling skill's discipline (one question at a time, with a recommended answer). Don't over-ask.
5. Don't write the solution space (変更方針 / 対象範囲 / 実装詳細 / 受け入れ条件 / テスト方針). Leave placeholders such as "解決空間。polish で詰める".
6. Pick a filename per the naming rule and create `issue/<name>.md`.
7. Report the created path. To go on and work out the solution, point to the coff-issue-polish skill.

## Exit bar

- The problem is correctly framed. The solution is left to polish.
<!--{"src":".coff/src/coff-issue-create.skill.md","md5":"93d5fb5fbb5ba394d6537044fe1850c5"} -->
