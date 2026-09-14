---
name: coff-issue-polish
description: Refine an issue under `issue/` into a self-contained spec that can be implemented on its own.
license: MIT
---

## Procedure

1. Read `.claude/skills/coff-detail-issue/SKILL.md` to get the template and quality bar.
2. Read the target issue and check the problem space first. Confirm the problem is correctly framed (meets the four validity angles); if not, re-frame 「目的 / 現状」 (bounce back to the problem space). Also check whether it bundles multiple problems whose adoption and completion can be judged independently; if so, propose splitting (one issue = one intent, per detail's purpose section). If the user explicitly instructs to bundle, comply and record that fact and reason as one line under 「決めたこと」.
3. Code investigation: actually read the related files, existing implementation, dependencies, and related skills / docs / issues, and fill in 「現状 / 実装詳細」 based on facts. Findings from external material go under 「調査記録」 with their sources; 「現状」 keeps only facts about the code and its operation.
4. Verify premises with a checklist: do the stated premises contradict the current code / do referenced file paths exist / is each 完了条件 executable with a stated check. Fix contradictions; move points needing the user's decision to 「未決」.
5. Sort the open points. Split points that come up into "the code answers this" and "the user must decide this". Resolve the former yourself in steps 3-4 — don't ask the human. Ask only the latter, before fixing anything. Discipline when asking: one question at a time, with a recommended answer for each, and look things up yourself when the code can answer. The exit of the Q&A is "this issue is implementable on its own", not "general agreement". Remove each settled point from 「未決」. Record under 「決めたこと」, one line each, only the choices that differ from the AI's recommendation and the choices left to the user; an approved recommendation goes into 設計方針. Never spec by guessing.
6. Work out the solution space. In 設計方針, gather the chosen approach and its rationale, the alternatives considered with rejection reasons, and what is out of scope (don't scatter rejected alternatives or the substance of decisions into other sections). In 完了条件, write only the conditions; put the way to check each one under 「完了条件の確認手段」 in 実装メモ with the same number. In 実装詳細, include the scope and representative file paths; reference skills/code rather than copying their procedures, and don't enumerate file paths that go stale quickly (per detail's bar).
7. (If needed) trial implementation. Where feasibility is uncertain, try it small. Safety procedure:
   - Before starting, `git stash` the working tree; after checking, `git stash pop` or discard.
   - If running in a separate process, delegate to the codex-delegate skill and collect only the result.
   - Either way, do not commit trial artifacts other than additions to the issue file.
8. Self-review with a checklist: everything above the fold (`## 実装メモ`) fits one screen (about 50 lines) / no empty sections or placeholders / each 完了条件 has a matching, executable check / premises match the code / no point the user should decide was silently decided / 未決 holds nothing but points awaiting decision, and is it empty / no exchanges or approved recommendations recorded under 決めたこと / 設計方針 does not contradict 決めたこと / nothing an implementer would stumble on / nothing useless or quick-to-stale for a later reader / no rejected alternatives or decision substance scattered outside 設計方針 / each rejection reason actually argues against that alternative (rewrite or drop ones that misread the alternative's premise or state generalities unrelated to it) / the prose follows the coff-japanese-tech-writing skill and has no sentences crammed with slashes or nested parentheses.
9. Update the 要約 under the title (2-3 lines: what and why) if needed, and overwrite the issue file. If the issue is in the old template (has `## 要約`, `## 人間が決めた判断`, etc.), rewrite it into the new template's structure. Preserve the leading frontmatter (including `status`) and don't change the `status` value (deciding completion is coff-issue-done's job). Write Japanese following the coff-japanese-tech-writing skill and check the line of argument with the coff-argument-gap-edit skill.
10. Run an implementer simulation. Spawn a fresh-context subagent (not a fork that inherits the conversation), have it read only the updated issue file, and return four things: an outline of its implementation plan / anything blocking it from starting / anything ambiguous / whether each 完了条件 is executable. Do not pass the polish session's conversation context (repo reads are allowed; the implementer can read the repo too). Resolve the findings only inside 「実装メモ」; touch anything above the fold only when 決めたこと or 未決 changes. Rerun only if you changed the issue. Cap it at two rounds; of what remains unresolved, leave the points needing the user's decision under 「未決」. Discard off-target findings; don't inflate the issue defending against them.
11. Report the changes applied and remaining tasks.

## Finish criteria

- An implementer can start from the issue alone. 未決 is empty.
<!--{"src":".coff/src/coff-issue-polish.skill.md","md5":"079402941492da63a2c815a111dc8f14"} -->
