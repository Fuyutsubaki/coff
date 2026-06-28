---
name: coff-detail-issue
description: Provide the shared conventions for issue management (location, naming, template, quality bar).
---

## Direct invocation

When `/coff-detail-issue` is invoked directly, just present the location / naming / template / quality bar below. Do not create or edit issues (creation is coff-issue-create's job; refinement is coff-issue-polish's).

## Location and naming

- Issues live in the repo's `issue/` directory, one issue = one markdown file (do not use GitHub Issues).
- Filename is `yymmddHHMM-<rnd2>.md`. `<rnd2>` is 2 random lowercase letters.
- Filename example:

  ```bash
  name="$(date +%y%m%d%H%M)-$(LC_ALL=C tr -dc 'a-z' </dev/urandom | head -c2)"
  # 例: 2606281430-xk  ->  issue/2606281430-xk.md
  ```

## Language

Write issue bodies in Japanese, following the japanese-tech-writing skill.

## Template

New issues follow this structure. The goal is that the issue alone is enough to start implementation.

```markdown
# <タイトル: 命令形で簡潔に>

## 背景・目的
<なぜ必要か / 解きたい問題>

## 現状
<今どうなっているか・関連する既存の挙動>

## 変更方針
<どう変えるか・採用案とその理由>

## 対象範囲・対象ファイル
<触る範囲。代表的なファイルパス>

## 実装詳細
<手順・データ構造・インターフェース。単体で実装できる粒度で>

## 受け入れ条件
- [ ] <完了の定義をチェックリストで>

## テスト方針
<どう検証するか>

## リスク・未解決
<懸念・要判断点・代替案。未確定はここに明示する>

## 参考・関連 issue
<リンク・関連する issue/ ファイル>
```

## Quality bar

- The test is "can you start implementation from this issue alone?".
- Don't leave vague wording or open questions in the body. Put anything unresolved under "リスク・未解決".
<!--{"src":".coff/src/coff-detail-issue.skill.md","md5":"b7907fd4b55d5cd3c8d38f66b1daced5"} -->
