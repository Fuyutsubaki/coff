---
name: coff-adopt-lessons
description: Sort session lessons into either an addition to a skill's norms or a new issue, and adopt them. The human decides adoption.
license: MIT
---

## Input

A list of lessons. Any form works (bullets from the conversation, a one-liner from the user, the 「教訓候補」 section of a coff-log-investigate skill report). Run in the main session (step 1 consults utterances in the conversation; do not delegate to a subagent).

## Procedure

1. Check each lesson against the original utterance. If the utterance exists in the conversation, quote it. If only an AI-written summary list exists, confirm the original intent per item with one question (attach a recommended answer; one question at a time).
2. Sort each item into three bins. Judge first by "is it needed or not"; "no existing skill has a place for it" is not a rejection reason (if needed, a place may be created).
   - 規範 (norm): a structural problem where the same failure recurs in the same situation, and that can be written as one sentence of procedure or judgment criteria. Destination is the relevant spot in an existing skill under `.coff/src/`.
   - issue: not settled by one sentence; requires an implementation or structural change.
   - 不採用 (not adopted): a one-off accident, or already implemented in an existing skill (point to the spot).

   An item that conflicts with a recorded design decision (a skill's leading comment, or an issue's 「人間が決めた判断」) is presented with the conflicting record attached. The human decides which to take.
3. Present one line per item and get the human's adoption decisions. Line form: "lesson / bin / destination or rejection reason (attach the conflicting record if any)". Write the destination down to the skill name and section. Recording reasons follows coff-detail-issue's 「判断の記録」 norm. Up to here, do not touch `.coff/src/`.
4. Only after decisions are in, execute the adopted items.
   - 規範: for each, file a problem-space-only issue with coff-issue-create, add the text under `.coff/src/`, build with `/coff-compile` (or the wrapper `/compile` if present), and close with coff-issue-done. Skip polish.
   - issue: file with coff-issue-create and stop. polish and onward are separate.
5. Report: destinations written, issues filed, and the not-adopted / needs-decision items with their reasons.

## Exit bar

- Adopted items live under `.coff/src/` or in an issue, and the adoption reasons are recorded.
<!--{"src":".coff/src/coff-adopt-lessons.skill.md","md5":"d1919c988ca2972e524fbde5cf43c05c"} -->
