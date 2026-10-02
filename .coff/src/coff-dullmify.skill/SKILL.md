---
name: coff-dullmify
description: skill のソースを指定言語の workflow と薄い skill に変換する。`<source> -o <outdir> --lang <ruby|cpp>` の全引数が必須。
license: MIT
coff-dist: true
allowed-tools: Write Bash(sh ${CLAUDE_SKILL_DIR}/assemble.sh *)
---

引数を `<source> -o <outdir> --lang <lang>` として解釈する。欠け、重複、余計な引数があれば、使い方を示して止まる。`<outdir>` は存在しないか空のディレクトリとする。ソースの frontmatter 値には `---` が含まれないことを前提とする。

この SKILL.md と同じディレクトリを基準に、`langs/<lang>/GUIDE.md` があるかをファイル参照で確かめる。なければ `langs/*/GUIDE.md` から対応言語を示して止まる。ソース、選んだ GUIDE、`review.md` をそれぞれファイル参照で読む。事前承認がないので、`cd`、`cat`、`ls` などのシェルのコマンドでは読まない。

最大 3 回、次の一巡を行う。

1. ソースの制御を GUIDE の API で workflow にする。問いは LLM にしかできない判断だけにし、副作用は補助関数で起こす。ソースの番号付き工程ごとに、番号がなければ段落ごとに、その節見出しと工程番号をソースと同じ言語のコメントで付ける。
2. GUIDE が定める名前の workflow 全体を `<outdir>/scripts/` に Write で書く。直すときも全体を Write で書き直す。事前承認は Write だけなので、Edit、`sed`、heredoc は承認で止まる。ほかのファイルを書かない。
3. この SKILL.md と同じディレクトリの `assemble.sh` の絶対パスを求め、`sh <絶対パス>/assemble.sh <lang> <source> <outdir>` を単独のコマンドとして呼ぶ。構文検査に落ちたら、その出力だけを使って次の回で直す。別の検査コマンドを使わない。
4. 組み立てに通ったら、`review.md` の雛形へソース、workflow、GUIDE の全文を埋め、会話を継承しない新しいサブエージェントに渡す。Claude Code では Agent、Codex では `spawn_agent` を使う。点検役には渡した内容だけで判定させる。最初の行が `合格` なら終了する。`不合格` なら指摘だけを使って次の回で直す。

原因が環境に見えても 3 回を行い、検査や点検を回避しない。3 回とも合格しなければ、`sh <絶対パス>/assemble.sh --discard <outdir>` を単独のコマンドとして呼んで `<outdir>` ごと片付け、失敗理由を報告する。
