---
name: coff-dullmify
description: skill ソースを指定言語の workflow と薄い skill に変換する。`/coff-dullmify <source> -o <outdir> --lang <ruby|cpp>`。
license: MIT
coff-dist: true
allowed-tools: Write Bash(sh ${CLAUDE_SKILL_DIR}/assemble.sh *)
---

# coff-dullmify

skill ソースを読み、手順の制御を指定言語の workflow に移す。LLM にしかできない判断だけを問いとして残す。

引数は `<source> -o <outdir> --lang <lang>` の形で、`<source>`、`<outdir>`、`<lang>` の 3 つとも必須とする。欠けていれば、この形を示して止まる。`source` と `outdir` は絶対パスに直す。ソースの frontmatter の値に `---` が含まれないことを前提とし、ここでは検査しない。

この SKILL.md と同じディレクトリを基準に同梱ファイルを参照する。`langs/<lang>/GUIDE.md` がなければ、`langs/*/GUIDE.md` から対応言語を列挙して、生成前に終了する。言語ごとの API、入口、workflow のファイル名、規則は対象言語の `GUIDE.md` を読む。点検方法と返答形式は `review.md` を読む。ソース、GUIDE、`review.md` はファイルを読むツールで読み、シェルのコマンドで読まない。

次の 1〜5 を 1 回とし、最大 3 回行う。回数は `--discard` を除く `assemble.sh` の呼び出しで数え、3 回呼んだら 4 回目は呼ばない。

1. ソースの各工程を逐次処理の workflow に写す。問いは LLM にしかできない判断に限り、ファイル操作とコマンド実行は GUIDE の補助関数で行う。ソースの番号付き手順の各項目（番号付き手順がなければ各段落）に対応するコードへ、節見出しと工程番号をソースと同じ言語のコメントで付ける。前の回が失敗した場合は、その構文エラーまたは点検の指摘を直す。
2. LLM が書くのは workflow 本体だけとする。GUIDE が定めるファイル名で `<outdir>/scripts/` へファイルを書くツールを使って書く。heredoc やシェル経由では書かない。`<outdir>` のほかのファイルには触れない。
3. この SKILL.md と同じディレクトリにある `assemble.sh` の絶対パスを求め、`sh <絶対パス>/assemble.sh <lang> <source> <outdir> <workflow>` だけを単独のコマンドとして呼ぶ。構文検査を別の方法で代用・回避しない。失敗したら `assemble.sh` が出した理由だけを読み、次の回へ進む。原因を調べるためにほかのコマンドを実行しない。
4. 組み立てに成功したら、`review.md` の雛形へソース、workflow、GUIDE の全内容を機械的に差し込む。会話を継承しない新しいサブエージェントを起動し、差し込んだプロンプトだけを渡して点検させる。Claude Code では Agent ツール、Codex では `spawn_agent` を使う。自分自身で代用せず、サブエージェントにファイルを読ませない。
5. 点検の最初の行が `合格` なら終了する。`不合格` または形式違反なら、`sh <絶対パス>/assemble.sh --discard <outdir>` を単独のコマンドとして呼び、指摘を読んで次の回へ進む。点検を回避しない。

3 回とも通らなければ、最後に `assemble.sh --discard <outdir>` を呼び、最後の失敗理由をそのまま報告して止まる。`<outdir>/SKILL.md` と `<outdir>/scripts/` を残さない。
