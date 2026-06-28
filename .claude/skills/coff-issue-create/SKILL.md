---
name: coff-issue-create
description: Scaffold a new issue under `issue/`.
---

## Procedure

1. Read `.claude/skills/coff-detail-issue/SKILL.md` to learn the location, naming, template, and quality bar.
2. If the `issue/` directory doesn't exist, create it with `mkdir -p issue`.
3. From the user's request, fill in the parts of the template you can (title / background & purpose / change plan, etc.). Write the body following the japanese-tech-writing skill. Leave undetermined items blank or as placeholders (filling in the details is polish's job).
4. Pick a filename per the naming rule and create `issue/<name>.md`.
5. Report the created path. If further refinement is wanted, point to the coff-issue-polish skill.
<!--{"src":".coff/src/coff-issue-create.skill.md","md5":"45c1666df1a29385749d48d099a887f4"} -->
