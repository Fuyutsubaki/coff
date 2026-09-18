---
name: coff-dullmify
description: skill ソースを決定論的な Perl workflow と薄い SKILL.md に分ける。`<source>.skill.md -o <dir>` でソースと出力先を指定する。
license: MIT
coff-dist: true
coff-dullmify: true
coff-bundle: [scripts, templates]
---

## 入出力

`<source>.skill.md -o <dir>` を受け取る。
引数の既定値は設けない。

`<dir>` に次の4ファイルを書く。

- `SKILL.md`
- `scripts/run.pl`
- `scripts/workflow.pl`
- `scripts/lib/Coff/Workflow.pm`

SKILL.md はソースの言語を保ち、フッタを付けない。
workflow.pl は `use utf8`、`sub workflow`、固有の補助関数だけで構成する。
driver と runtime は同梱物をバイト単位で複製する。

## 手順

1. 引数を検査する。
   ソースは1個の `*.skill.md`、出力先は1個の `-o <dir>` とする。
   ソースが存在しない場合、空の場合、引数が余る場合は失敗する。
2. ソース全文を UTF-8 で読む。
   `<dir>/scripts/workflow.pl` が存在すれば、全文を UTF-8 で読み、既存 workflow とする。
3. topic `workflow` を問い、入力に `{source, existing}` を渡す。
4. topic `topics` を問い、入力に `{source}` を渡す。
5. workflow の答えを検査する。
   空、`sub workflow` がない、Markdown フェンス、shebang、`use` 宣言、`run_workflow`、生成フッタを含む答えは失敗とする。
6. topics の答えを検査する。
   空、frontmatter、Markdown フェンスを含む答えは失敗とする。
7. workflow.pl を `use utf8`、空行、workflow の答えの順に組み立てる。
8. SKILL.md の frontmatter を組み立てる。
   ソースの frontmatter から `coff-*` と `allowed-tools` を除き、`allowed-tools: Bash(perl ${CLAUDE_SKILL_DIR}/scripts/run.pl *)` を加える。
9. SKILL.md の本文を `templates/skill-prefix.md`、topics の答え、`templates/skill-suffix.md` の順に組み立てる。
   定型は変更せずに差し込む。
10. workflow.pl を一時ファイルへ書き、`perl -c` を通す。
    構文検査に失敗した場合は `<dir>` へ何も書かない。
11. 構文検査後に4ファイルを書く。
    各ファイルを出力先と同じディレクトリの一時ファイルへ書き、rename で置き換える。
12. `dullmified: <source> -> <dir>` を報告する。

## topic `workflow`

入力の `source` を読み、`sub workflow` とその skill に固有の補助関数だけを Perl で返す。
`existing` が空でなければ既存の構造を保ち、必要な変更に限る。
Markdown フェンス、shebang、`use` 宣言、`run_workflow`、生成フッタを含めない。

副作用を引数なしの `step { ... }` に置き、失敗は `die` で表す。
LLM の判断とユーザーへの問いは `llm(topic, input)` で表す。
ユーザーへの問いかどうかは topic の判断基準に書く。
時計と乱数を使わず、hash のキーを sort してから処理する。
effect を `eval {}` で囲まない。

Perl 5.30 で動く構文と core モジュールだけを使う。
追加の core モジュールは補助関数内で `require` し、完全修飾名で呼ぶ。
補助関数ごとに、目的を示す日本語のコメントを直前に1行以上書く。
生成時に `use utf8` を加えるため、答えには書かない。

## topic `topics`

入力の `source` から、workflow が使う topic ごとの判断基準を Markdown で返す。
各 topic について、入力、答えの形式、判断基準を書く。
ユーザーへの問いは AskUserQuestion で提示するよう指示する。
frontmatter、共通の往復手順、完了報告、Markdown フェンスを含めない。
ソースと同じ言語で端的に書く。

## ルール

- md5、フッタ、翻訳、最終出力先を扱わない。
- ソースと既存 workflow の内容を変更しない。
- workflow と topics の答えをファイル操作に使う前に検査する。
- 構文検査より前に出力先を変更しない。
