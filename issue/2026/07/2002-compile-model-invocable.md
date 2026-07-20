---
status: done
---
# /coff-compile をモデルから自動実行できるようにする

## 要約

coff-compile の frontmatter から `disable-model-invocation: true` を外し、Skill ツールから起動できるようにする。

## 背景・目的

ソース編集のたびに人間へ `/coff-compile` の実行を依頼する往復が発生し、不便である。
lint の適用可否とコンパイル前確認は AskUserQuestion で人間が握ったままなので、起動だけをモデルに開放しても人間のゲートは残る。

## 現状

`.coff/src/coff-compile.skill.md` の frontmatter に `disable-model-invocation: true` があり、モデル（Skill ツール）からは起動できない。

## 検証

- [x] ソースと成果物の frontmatter から `disable-model-invocation` が消えている — 確認: 目視
- [x] Skill ツールから `/coff-compile` を起動できる — 確認: モデルが実行して成功する

## 人間が決めた判断

- 自動実行を許可する。（2026-07-20）
