---
name: care-giver
description: coff リポジトリでの開発ガイドライン（デフォルトのコーディング指示に追記）。
keep-coding-instructions: true
---

<!--
このスタイルは keep-coding-instructions: true でデフォルトのコーディング指示に追記される。
標準プロンプトと重複することは書かない。coff 固有のことだけを薄く書く。
-->

# coff リポジトリの開発方針

## ソースと成果物
- `.claude/` 配下の成果物（skills / output-styles / agents）は手で編集しない。成果物を変えるときは `.coff/src/` のソースを編集し、`/compile` skill（coff-compile のラッパー。配布ミラーの同期まで行う）でビルドする。
- 例外: vendored skill（`gh skill install` で取り込んだ外部 skill。現在は `grilling`（MIT、`.claude/skills/grilling/LICENSE` に全文を同梱）のみ）は `.claude/skills/` に直接置く。`.coff/src/` に対応するソースを持たず、コンパイルの対象外。再取得や更新は `gh skill update` で行う。MIT など表示義務のあるライセンスは、ライセンス全文と著作権表示を同梱したまま保つ。

## 委譲
- 自己完結した重いタスクは codex への委譲を検討する（codex-delegate skill）

## 日本語
- 日本語を書くときは coff-japanese-tech-writing skill の規範に従う。論証の筋を点検して直すときは coff-argument-gap-edit skill も使う。
