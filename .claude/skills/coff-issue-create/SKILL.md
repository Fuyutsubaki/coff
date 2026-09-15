---
name: coff-issue-create
description: Scaffold a new issue under `issue/`.
license: MIT
---

## Procedure

1. Read `../coff-detail-issue/SKILL.md` (relative to this SKILL.md's parent directory, not the cwd) to get the location, naming, template, and quality bar.
2. Create the month directory with `mkdir -p "issue/$(date +%Y/%m)"`.
3. Write only the problem space. From the user's request, articulate 「タイトル / 要約 / 目的 / 現状」. Write the body following the coff-japanese-tech-writing skill.
4. Examine problem validity from detail's four angles. Also check whether the request bundles multiple problems whose adoption and completion can be judged independently; if so, propose filing them separately (one issue = one intent, per detail's purpose section). Leave rejected framings as one sentence under 目的, and doubts that need the user's decision under 「未決」. Do not do deep code investigation (minimal reading to confirm the problem exists is fine). Ask only when the problem's framing (kind, purpose, success condition) cannot be determined, and ask lightly. Discipline: one question at a time, with a recommended answer for each, and look things up yourself when the code can answer. No exhaustive interrogation; stop once the framing is settled.
5. Do not write the solution space (follow detail's ownership split).
6. Name the file per the naming rule and create `issue/<yyyy>/<mm>/<name>.md`. Put `status: open` frontmatter at the top (per detail's status spec).
7. Report the created path. If the solution is to be refined next, point to the coff-issue-polish skill.

## Exit criteria

- The problem is correctly framed. The solution is left to polish.
<!--{"src":".coff/src/coff-issue-create.skill.md","md5":"f9b73af494bc538a9b92584dbd6656aa"} -->
