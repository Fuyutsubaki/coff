---
name: coff-dullmify
description: `.coff/src/<name>.skill.md` を決定論的な Perl workflow と薄い SKILL.md に分ける。`<name> [--out <dir>]` を受け取り、既定では `.claude/skills/<name>/` へ出力する。
license: MIT
coff-dist: true
coff-bundle: [scripts, templates]
allowed-tools: Bash(perl ${CLAUDE_SKILL_DIR}/scripts/run.pl *)
---

## workflow の実行

`perl ${CLAUDE_SKILL_DIR}/scripts/run.pl --workflow dullmify.pl start $ARGUMENTS` を実行し、JSON 応答を読む。

応答に `ask` があれば、`kind` と `topic` に従って答えを作り、答えだけを標準入力から `perl ${CLAUDE_SKILL_DIR}/scripts/run.pl --workflow dullmify.pl resume <run> <index>` へ渡す。
答えは single-quoted heredoc でそのまま渡す。
`done: true` まで繰り返す。

会話のコンテキストを失ったら `--workflow dullmify.pl status <run>` で未回答の問いを取得する。
run の終了には `--workflow dullmify.pl cancel <run>`、7 日より古い run の削除には `--workflow dullmify.pl gc` を使う。

## topic `workflow`

入力の `source` を読み、`sub workflow` とその skill に固有の補助関数だけを Perl で返す。
既存の `workflow.pl` が `existing` にあれば、必要な変更に限る。
Markdown フェンス、shebang、`use` 宣言、`run_workflow` の呼び出し、生成フッタを含めない。

副作用を引数なしの `step { ... }` に置き、失敗は `die` で表す。
対象ごとの失敗を続行可能な報告へ変える場合は `attempt { ... }` を使う。
`llm` と `user` には topic と入力だけを渡す。
時計と乱数を使わず、hash のキーを sort してから回す。
effect を素の `eval` で囲まない。

Perl 5.30 で動く構文と core モジュールだけを使う。
`run.pl` が読み込む `Digest::MD5`、`Encode`、`File::Basename`、`File::Find`、`File::Path`、`File::Spec`、`JSON::PP` と、`Coff::Workflow` の `llm`、`user`、`step`、`attempt`、`publish_files` を使う。
生成時に `use utf8` が加わるため、答えには書かない。

## topic `topics`

入力の `source` から、workflow が使う `llm` と `user` の topic ごとの判断基準を Markdown で返す。
問いに含まれる入力、答えの形式、判断基準だけを書く。
frontmatter、共通の往復手順、完了報告、Markdown フェンスを含めない。
ソースと同じ言語で端的に書く。

## 完了時の報告

応答が `done: true` になったら `report` を提示する。
空の report は提示しない。
