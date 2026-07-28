---
name: coff-detail-issue
description: Provide the shared conventions for issue management (purpose, location, naming, template, quality bar).
license: MIT
---

## Direct invocation

When `/coff-detail-issue` is invoked directly, just present the purpose / location / naming / template / quality bar below. Do not create or edit issues (creation is coff-issue-create's job; refinement is coff-issue-polish's).

## Purpose

An issue is a record of a unit of work shared between the AI and the human. While open, read it as an implementation contract (a spec an implementer can start from on its own); once done, read it as long-term memory of design decisions. The 「人間が決めた判断」 section and polish's sorting of open points are the mechanisms that keep the boundary between AI and human decisions in the body.

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

## Language

Write issue bodies in Japanese, following the coff-japanese-tech-writing skill.

## Problem space and solution space

An issue is built in two stages: framing the problem, then working out the solution. Roles split along this axis.

- The problem space (背景・目的 / 現状) is framed by coff-issue-create.
- The solution space (要約 / 変更方針 / 実装詳細 / 検証) is worked out by coff-issue-polish.
- The cross-cutting sections (人間が決めた判断 / リスク・未解決 / 参考・関連 issue) are added by both stages.

### Problem validity

Both when create frames the problem and when polish checks the problem at its entry, examine validity from these angles:

- Is this actually a problem worth solving?
- Is it already solved?
- Is the question framed correctly?
- Is there another way to frame it?

Leave doubts and rejected framings under 「リスク・未解決」.

## Template

Write new issues with the structure below.

```markdown
---
status: open   # open（未完了）| done（完了）
---
# <タイトル: 命令形で簡潔に>

## 要約
<2、3行: 何をなぜどう変えるか>

## 背景・目的
<なぜ必要か / 解きたい問題>

## 現状
<今どうなっているか・関連する既存の挙動（事実）>

## 変更方針
<どう変えるか。採用案とその理由、検討した代替案と却下理由をここに集約し、他の節に書かない>

## 実装詳細
<触る範囲と代表的なファイルパス、手順・データ構造・インターフェース。単体で実装できる粒度で>

## 検証
- [ ] <完了の条件> — 確認: <確認手段>

## 人間が決めた判断
<何を人間が決めたか、理由の要点、日付だけを残す。決定の実体は変更方針に書く>

## リスク・未解決
<懸念・要判断点。未確定はここに明示する>

## 参考・関連 issue
<関連する issue やファイル>
```

Ownership: create fills 背景・目的 and 現状; polish fills the rest of the solution space (要約, 変更方針, 実装詳細, 検証 — writing 要約 last). The three cross-cutting sections are added by both stages. create leaves the polish-owned sections as placeholders. Do not write ownership into the issue's headings.

Reference format: anywhere in the body, refer to issues and past records as "path + one phrase (what the record is)".

Recording decisions: write the reasons behind the user's adoptions and rejections at the granularity and in the vocabulary of what they said. Condensing to the gist is fine, but do not swap in a different reason (a better-sounding one such as risk avoidance or erring on the safe side).

Keep information valuable to a later reader, and don't accumulate scaffolding needed only at authoring time.

- Keep: the chosen approach and its rationale, rejected alternatives and why, constraints that matter later (key types / state transitions / protocols, constraints found via a trial implementation), and representative entry-point files needed to understand the existing design.
- Don't accumulate: verbatim copies of a skill's or code's procedure (the real thing lives there, so a copy is double-maintained and goes stale), broad file-path enumerations, session narrative, and notes that duplicate other sections.

But 検証 (completion conditions and how to check them) is needed to implement, so don't drop it for the sake of brevity. The 検証 checkboxes are ticked by whoever implemented the issue, after running each stated check; have them all ticked before invoking done.

## Quality bar

The bar splits in two:

- create's exit: the problem is correctly framed (meets the four problem-validity angles).
- polish's exit: the issue alone is enough to start implementation.

Don't leave vague wording or open questions in the body. Put judgment calls under 「リスク・未解決」, and decisions the human has settled under 「人間が決めた判断」.
<!--{"src":".coff/src/coff-detail-issue.skill.md","md5":"173caf928114ee6666c056463d1bc320"} -->
