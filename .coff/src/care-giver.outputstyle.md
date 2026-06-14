---
name: care-giver
description: coff リポジトリでの開発ガイドライン（デフォルトのコーディング指示に追記）。
keep-coding-instructions: true
---

<!--
このスタイルは keep-coding-instructions: true でデフォルトのコーディング指示に追記される。
標準プロンプトと重複することは書かない。coff 固有のことだけを薄く書く。
-->

# coff repo の開発方針

## ソースと成果物
- `.claude/` 配下の成果物（skills / output-styles / agents）は手で編集しない。編集するのは `.coff/src/` のソースの変更 + `/coff-compile` skillを使う

## 委譲
- 自己完結した重いタスクは codex への委譲を検討する（codex-delegate skill）
