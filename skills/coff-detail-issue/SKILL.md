---
name: coff-detail-issue
description: Provide the shared conventions for issue management (purpose, readers, location, naming, template, quality bar).
license: MIT
---

## Direct invocation

When `/coff-detail-issue` is invoked directly, just present the purpose / location / naming / template / quality bar below. Do not create or edit issues (creation is coff-issue-create's job; refinement is coff-issue-polish's).

## Purpose

An issue is a record of a unit of work shared between the AI and the human. While open, read it as an implementation contract (a spec an implementer can start from on its own); once done, read it as long-term memory of design decisions.

While open, the primary reader is the user, who reads everything above the fold (`## 実装メモ`) in a few minutes. The implementing AI also reads below the fold and starts work. The 「決めたこと」 section and polish's sorting of open points are the mechanisms that keep the boundary between AI and human decisions in the body.

The correctness of the record is judged by its content at the point it lands on master. On a branch, a committed issue may be rewritten — appending is not required.

Admission bar:

- Every change goes through an issue — as strictly as changes go through PRs in team development.
- The unit of an issue is one intent, and it may be as coarse as a PR. Don't bundle problems whose adoption and completion can be judged independently. Example: fixing notation inconsistencies across many files is one intent; several mutually independent cleanups are not.
- A minor fix subordinate to the intent of the issue being worked on may ride along with that issue.
- For a standalone minor change, filing a few-line problem-space-only issue and marking it done immediately is fine.

Issues do not carry team issue management (priority, assignee, due date).

## Location and naming

- Issues live under the repo's `issue/<yyyy>/<mm>/` directory (bucketed by the year/month they were created). One issue is one Markdown file (do not use GitHub Issues).
- Filename is `<ddHH>-<slug>.md` (`dd`=day, `HH`=hour; the year/month is carried by the directory, so it's not repeated in the prefix). `<slug>` is a short kebab-case description of the content (e.g. `fix-hoge`, `add-login`).
- Location and filename example:

  ```bash
  dir="issue/$(date +%Y/%m)"   # 例: issue/2026/07
  ts="$(date +%d%H)"           # 例: 0222
  mkdir -p "$dir"
  # <slug> は内容を表す短いケバブケース。例: fix-hoge
  # -> issue/2026/07/0222-fix-hoge.md
  ```

## Status

An issue's completion state lives in a `status` key in YAML frontmatter at the top of the file.

- The value range is `open` (not done) and `done` (done) — two values.
- New issues are created by coff-issue-create with `status: open`.
- On completion, coff-issue-done updates it to `status: done`.
- An issue with no frontmatter, or no `status`, is treated as `open` (a default so existing issues need not be touched).

Even when done, the issue file stays in place.

The completion context (when, and by which change, it was completed) is not recorded in the issue; derive it from git.

```bash
git blame -L '/^status:/,+1' -- <issueファイル>   # 完了コミットと日時
gh pr list --search <ハッシュ> --state merged      # そのコミットを含む PR = 実装の所在
```

Premise: the change to done and the implementation go into the same PR.

Listings are generated on demand by coff-issue-list. Do not keep a listing file (README or the like).

## Language

Write issue bodies in Japanese, following the coff-japanese-tech-writing skill. An issue is a spec, though, so write the file names, function names, and identifiers it refers to concretely; that skill's rule against naming things not referenced later does not apply to issues.

## Problem space and solution space

An issue is built in two stages: framing the problem, then working out the solution. Roles split along this axis.

- The problem space (要約 / 目的 / 現状) is framed by coff-issue-create.
- The solution space (設計方針 / 完了条件 / 実装メモ) is worked out by coff-issue-polish.
- The cross-cutting sections (決めたこと / 未決) are added by both stages.

### Problem validity

Both when create frames the problem and when polish checks the problem at its entry, examine validity from these angles:

- Is this actually a problem worth solving?
- Is it already solved?
- Is the question framed correctly?
- Is there another way to frame it?

A rejected framing is left as a one-sentence "not covered" note under 目的 at the create stage, and polish gathers it into 設計方針's out-of-scope list. Doubts that need the user's decision go under 「未決」.

## Template

Write new issues with the structure below.

```markdown
---
status: open   # open（未完了）| done（完了）
---
# <タイトル: 命令形で簡潔に>

<要約 2、3 行: 何を、なぜ>

## 目的
<解きたい問題と、解けたときの状態。扱わないことがあれば一文で>

## 現状
<コードと運用の事実。ファイル名や関数名で指す。外部資料の調査は書かない>

## 設計方針
<採用案と理由。却下した代替案は理由を一言添えて箇条書き。対象外を明示する>

## 決めたこと
- <決定>（<理由の要点。ユーザーの語彙で>）

## 未決
- <ユーザーの判断待ちの論点>

## 完了条件
- [ ] <完了の条件>

## 実装メモ

### 実装詳細
<触る範囲と代表的なファイルパス、手順、データ構造、インターフェース。単体で実装できる粒度で>

### 完了条件の確認手段
1. <上の完了条件 1 番目の確認手段>

### 調査記録
<技術調査の結果と出典>

### 参考
<関連する issue やファイル。パス+一言>
```

Ownership and empty sections: create writes only 要約, 目的, and 現状 (plus 決めたこと / 未決 when there is something to record). Never leave polish-owned sections as placeholders. An issue without 「設計方針」 is read as not yet polished. 決めたこと, 未決, 調査記録, and 参考 are optional: omit the section when there is nothing to write. Do not write ownership into the issue's headings.

The fold: everything below `## 実装メモ` is for the implementer; the user need not read it, and no preamble is needed under the heading. Keep everything above `## 実装メモ` within one screen (about 50 lines). If it overflows, raise the level of summary; if there are multiple intents, split.

決めたこと: record only the points where the user chose differently from the AI's recommendation, and the points the AI could not decide and left to the user. An approved recommendation just goes into 設計方針. One decision per line, as `<decision>（<gist of the reason>）`, with no date (git has it). Do not record exchanges ("agreed", "replied OK"). Write the reason in the user's own vocabulary; do not swap in a different reason (a better-sounding one such as risk avoidance or erring on the safe side). 設計方針 must not contradict the decisions recorded here.

未決: only points awaiting the user's decision. A concern goes under 現状 if it is a fact, under 設計方針 as out-of-scope if it is a judgment, and nowhere otherwise. When empty, omit the section.

完了条件: write only the conditions. Put the way to check each one under 「完了条件の確認手段」 in 実装メモ with the same number. Conditions and their checks are needed to implement, so don't drop them for the sake of brevity. The checkboxes are ticked by whoever implemented the issue, after running each check; have them all ticked before invoking done.

Reference format: anywhere in the body, refer to issues and past records as "path + one phrase (what the record is)".

Keep information valuable to a later reader, and don't accumulate scaffolding needed only at authoring time.

- Keep: the chosen approach and its rationale, rejected alternatives and why, constraints that matter later (key types / state transitions / protocols, constraints found via a trial implementation), and representative entry-point files needed to understand the existing design.
- Don't accumulate: verbatim copies of a skill's or code's procedure (the real thing lives there, so a copy is double-maintained and goes stale), broad file-path enumerations, session narrative, and notes that duplicate other sections.

## Quality bar

The bar splits in three:

- create's exit: the problem is correctly framed (meets the four problem-validity angles).
- polish's exit: the issue alone is enough to start implementation, and 未決 is empty.
- done's exit: every 完了条件 is ticked, 未決 is empty, and the body matches what was built.

Before invoking done, the implementer rewrites 設計方針 and 実装メモ to match what was actually built. Remaining work goes to a separate issue or is dropped.

Don't leave vague wording or open questions in the body.
<!--{"src":".coff/src/coff-detail-issue.skill.md","md5":"09867b59d0129803fb227f3e06a364d3"} -->
