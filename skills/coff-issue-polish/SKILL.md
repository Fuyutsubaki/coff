---
name: coff-issue-polish
description: Refine an issue under `issue/` into a self-contained spec that can be implemented on its own.
license: MIT
---

## Procedure

1. Read `.claude/skills/coff-detail-issue/SKILL.md` to get the template and quality bar.
2. Read the target issue and check the problem space first. Confirm the problem is correctly framed (meets the four validity angles); if not, re-frame 「目的 / 現状」 (bounce back to the problem space). Also check whether it bundles multiple problems whose adoption and completion can be judged independently; if so, propose splitting (one issue = one intent, per detail's purpose section). 
3. Code investigation: actually read the related files, existing implementation, dependencies, and related skills / docs / issues, and fill in 「現状 / 実装詳細」 based on facts. Findings from external material go under 「調査記録」 with their sources.
4. Verify premises with a checklist: do the stated premises contradict the current code / do referenced file paths exist. Fix contradictions; move points needing the user's decision to 「未決」.
5. Sort the open points. Split points that come up into "the code answers this" and "the user must decide this". Resolve the former yourself in steps 3-4 — don't ask the human. Ask only the latter, before fixing anything. Discipline when asking: one question at a time, with a recommended answer for each, and look things up yourself when the code can answer. The exit of the Q&A is "this issue is implementable on its own", not "general agreement". Remove each settled point from 「未決」; record the conclusion the user chose under 「決めたこと」 and elaborate it in 設計方針. Never spec by guessing.
6. Write the solution space (設計方針 / 完了条件 / 実装メモ) per detail's template rules. In 設計方針, gather the chosen approach and its rationale, the alternatives considered with rejection reasons, and what is out of scope; don't scatter them into other sections. 実装メモ follows detail's "Keep / Don't accumulate" bar.
7. (If needed) trial implementation. Where feasibility is uncertain, try it small. Safety procedure:
   - Before starting, `git stash` the working tree; after checking, `git stash pop` or discard.
   - If running in a separate process, delegate to the codex-delegate skill and collect only the result.
   - Either way, do not commit trial artifacts other than additions to the issue file.
8. Update the 要約 under the title (2-3 lines: what and why) if needed, and overwrite the issue file. If the issue is in the old template (has `## 要約`, `## 人間が決めた判断`, etc.), rewrite it into the new template's structure. Preserve the leading frontmatter (including `status`) and don't change the `status` value (deciding completion is coff-issue-done's job). Write Japanese following the coff-japanese-tech-writing skill and check the line of argument with the coff-argument-gap-edit skill.
9. Cleanup. Check the whole written-out issue against detail's template rules and polish's exit bar, fix it, and overwrite. Cover what this session wrote, not only inherited content. Remove anything useless, or quick to go stale, for a later reader. In addition, check:
   - Silent decisions: was any point the user should decide silently decided?
   - Title and 要約: do they narrate history?
   - 決めたこと: is it the list of decisions currently in force?
   - 完了条件 and 完了条件の確認手段: do they rest on a premise this round's decisions broke?
   - Rejection reasons: does each actually argue against that alternative (rewrite or drop ones that misread the alternative's premise or state generalities unrelated to it)?
   - Rejection reasons and 実装メモ: do vocabulary or premises from an earlier implementation or an earlier polish remain?
   - Line count above the fold: is the line number of `## 実装メモ` within the guideline? If over, fix it. Do not report it as a remaining task.
10. Run an implementer simulation. Spawn a fresh-context subagent (not a fork that inherits the conversation), have it read only the updated issue file, and return four things: an outline of its implementation plan / anything blocking it from starting / anything ambiguous / whether each 完了条件 is executable. Do not pass the polish session's conversation context (repo reads are allowed; the implementer can read the repo too). Resolve the findings in 「実装メモ」 as a rule (an unclear procedure goes to 「完了条件の確認手段」; do not write procedures in 実装詳細); touch anything above the fold only when 完了条件, 設計方針, 決めたこと, or 未決 actually changes. Rerun only if you changed the issue. Cap it at two rounds; of what remains unresolved, settle the points needing the user's decision by asking on the spot under step 5's discipline (do not finish with them left under 未決). Discard off-target findings; don't inflate the issue defending against them.
11. Get one review. Spawn fresh-context subagents in parallel, one per lens, and pass only the issue file and the implementation-plan outline returned by the last simulation. Use the same conditions as the simulation (no fork, no conversation context, repo reads allowed). Do not let them modify files or raise findings outside their lens.

    Lenses:

    1. YAGNI (unused extension points, rechecks of what is already guaranteed, excess insurance)
    2. Is the spec needlessly complex?
    3. Is the scale of the change proportionate to the purpose?
    4. Does the plan include the user entry point (skill / CLI / UI) the issue calls for? Is that entry point bloated with a copy of the spec?
    5. Quality as a record (history narration, contradictions between sections, stale premises). Have this lens's subagent read the same detail file as step 1 as its criteria

    Handle findings with step 5's sorting. Discard off-target findings, fix those needing no decision, and settle those needing the user's decision by asking on the spot. Fixes may land above or below the fold. If 設計方針 or 完了条件 changed, rerun step 10's simulation exactly once (counted separately from the two-round cap). Finally, recheck anything fixed after the cleanup against step 9's items.
12. Report the changes applied and remaining tasks.

## Finish criteria

- Meets detail's exit bar for polish.
<!--{"src":".coff/src/coff-issue-polish.skill.md","md5":"508ad81476bbc658f9e4e8e04eb6255a"} -->
