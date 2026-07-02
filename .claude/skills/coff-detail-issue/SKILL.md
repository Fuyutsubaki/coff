---
name: coff-detail-issue
description: Provide the shared conventions for issue management (location, naming, template, quality bar).
---

## Direct invocation

When `/coff-detail-issue` is invoked directly, just present the location / naming / template / quality bar below. Do not create or edit issues (creation is coff-issue-create's job; refinement is coff-issue-polish's).

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

## Language

Write issue bodies in Japanese, following the japanese-tech-writing skill.

## Problem space and solution space

An issue is built in two stages: framing the problem, then working out the solution. Roles split along this axis.

- The problem space (背景・目的 / 現状) is framed by coff-issue-create.
- The solution space (変更方針 / 対象範囲・対象ファイル / 実装詳細 / 受け入れ条件 / テスト方針) is worked out by coff-issue-polish.
- The cross-cutting sections (人間が決めた判断 / リスク・未解決 / 参考・関連 issue) are added by both stages.

### Problem validity

Both when create frames the problem and when polish checks the problem at its entry, examine validity from these angles:

- Is this actually a problem worth solving?
- Is it already solved?
- Is the question framed correctly?
- Is there another way to frame it?

Leave doubts and rejected framings under "リスク・未解決".

## Template

Write new issues with the structure below. The 〔 〕 on each heading marks ownership.

```markdown
---
status: open   # open（未完了）| done（完了）
---
# <タイトル: 命令形で簡潔に>

## 背景・目的  〔問題 / create〕
<なぜ必要か / 解きたい問題>

## 現状  〔問題 / create〕
<今どうなっているか・関連する既存の挙動（事実）>

## 変更方針  〔解 / polish〕
<どう変えるか・採用案とその理由。検討した代替案と却下理由も残す>

## 対象範囲・対象ファイル  〔解 / polish〕
<触る範囲。代表的なファイルパス>

## 実装詳細  〔解 / polish〕
<手順・データ構造・インターフェース。単体で実装できる粒度で>

## 受け入れ条件  〔解 / polish〕
- [ ] <完了の定義をチェックリストで>

## テスト方針  〔解 / polish〕
<どう検証するか>

## 人間が決めた判断  〔横断〕
<AI でなく人間が決めた点を残す。各項目に「決定内容 / 理由 /（未確定なら）要確認」>

## リスク・未解決  〔横断〕
<懸念・要判断点・代替案。未確定はここに明示する>

## 参考・関連 issue  〔横断〕
<リンク・関連する issue/ ファイル>
```

create fills only the problem space and leaves the solution space as placeholders. polish works out the solution space.

An issue is long-term memory of design decisions. Keep information valuable to a later reader, and don't accumulate scaffolding needed only at authoring time.

- Keep: the chosen approach and its rationale, rejected alternatives and why, constraints that matter later (key types / state transitions / protocols, constraints found via a trial implementation), and representative entry-point files needed to understand the existing design.
- Don't accumulate: verbatim copies of a skill's or code's procedure (the real thing lives there, so a copy is double-maintained and goes stale), broad file-path enumerations, session narrative, and risk notes that duplicate other sections.

But 受け入れ条件 and テスト方針 are needed to implement, so don't drop them for the sake of brevity.

## Quality bar

The bar splits in two:

- create's exit: the problem is correctly framed (meets the four problem-validity angles).
- polish's exit: the issue alone is enough to start implementation.

Don't leave vague wording or open questions in the body. Put judgment calls under "リスク・未解決", and decisions the human has settled under "人間が決めた判断".
<!--{"src":".coff/src/coff-detail-issue.skill.md","md5":"6e7dbbb8bd2d3eb7980a8b7d9f5e7d1c"} -->
