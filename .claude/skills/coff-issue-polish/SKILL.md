---
name: coff-issue-polish
description: Refine an issue under `issue/` into a self-contained spec that can be implemented on its own.
---

## Procedure

1. Read `.claude/skills/coff-detail-issue/SKILL.md` to learn the template and quality bar.
2. Read the target issue and, against the template and bar, find missing sections and vague points.
3. Code investigation: actually read the relevant files, existing implementation, and dependencies, and fill in "現状 / 対象範囲 / 実装詳細" based on facts.
4. Premise verification: check that the stated premises don't contradict the current code. Fix contradictions; move judgment calls to "リスク・未解決".
5. (If needed) trial implementation. Try small experiments to confirm feasibility where it's doubtful. Safety protocol:
   - Before starting, stash the working tree with `git stash`; after checking, restore with `git stash pop` or discard it.
   - To run it in a separate process, delegate to the codex-delegate skill and only collect the result.
   - In all cases, don't leave trial-implementation artifacts in the commit tree beyond edits to the issue file.
6. Do a few rounds of multi-perspective self-review: will an implementer get stuck? are the acceptance criteria verifiable? is the test plan sufficient? any gaps? are the risks covered?
7. Overwrite the issue file. Write Japanese prose following the japanese-tech-writing skill, and check the logic of the argument with the argument-gap-edit skill. Report the changes applied and the remaining work.

## Done bar

- An implementer can start from the issue alone.
<!--{"src":".coff/src/coff-issue-polish.skill.md","md5":"95aa4fcc4bed02f0f06c1434304cada4"} -->
