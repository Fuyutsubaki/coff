---
name: coff-issue-polish
description: Refine an issue under `issue/` into a self-contained spec that can be implemented on its own.
---

## Procedure

1. Read `.claude/skills/coff-detail-issue/SKILL.md` to learn the template and quality bar.
2. Read the target issue and first check the problem space. Confirm it meets the four problem-validity angles and the problem is correctly framed; if it's broken, re-frame 背景・目的 / 現状 (hand back to the problem space).
3. Code investigation: actually read the relevant files, existing implementation, dependencies, related skills, docs, and related issues, and fill in 現状 / 対象範囲 / 実装詳細 based on facts.
4. Verify premises with a checklist: do the stated premises not contradict the current code / do the referenced file paths exist / are the acceptance criteria verifiable. Fix contradictions; move judgment calls to "リスク・未解決".
5. Sort the open points. Split the points that come up into "answerable from code" and "needs the user's decision". Resolve the former yourself via steps 3-4; don't ask the human. Only for the latter, ask before deciding; when you ask, read `.claude/skills/grilling/SKILL.md` and follow its discipline. Set the exit to "the issue becomes implementable on its own", not "generic agreement". Record decisions the human makes under the "人間が決めた判断" section. Don't lock in guesses as spec.
6. Work out the solution space. In 変更方針, keep the chosen approach plus the alternatives considered and why they were rejected. Fill in 受け入れ条件 and テスト方針 too. For 実装詳細, don't copy a skill's or code's procedure verbatim — reference it instead — and don't enumerate file paths that go stale (follow detail's bar).
7. (If needed) trial implementation. Try small experiments where feasibility is uncertain. Safety steps:
   - Before starting, stash the working tree with `git stash`; after checking, restore with `git stash pop` or discard it.
   - To run it in a separate process, delegate to the codex-delegate skill and only collect the result.
   - In all cases, don't include trial-implementation artifacts in the commit beyond edits to the issue file.
8. Self-review with a checklist: is each template section filled / are the acceptance criteria verifiable / is the test plan sufficient / do the premises match the code / are the risks covered / have you silently locked in a point you should have asked the user about / is there anywhere an implementer would get stuck / have you written anything useless to a later reader or that goes stale quickly.
9. Overwrite the issue file. Preserve the leading frontmatter (including `status`) and don't change the `status` value (marking done is coff-issue-done's job). Write Japanese prose following the japanese-tech-writing skill, and check the logic of the argument with the argument-gap-edit skill. Report the changes applied and the remaining work.

## Done bar

- An implementer can start from the issue alone.
<!--{"src":".coff/src/coff-issue-polish.skill.md","md5":"fe7910dd19cd57aac85dbe0e5488c3d1"} -->
