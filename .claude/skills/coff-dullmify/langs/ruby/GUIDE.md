# Ruby workflow ガイド

workflow のファイル名は `workflow.rb` とし、引数を取らない `workflow` メソッドを定義する。戻り値を文字列にしたものが最終的な report になる。Ruby 3.0 以上を対象にする。

## API

- `Dullmify.arguments`：skill に渡された引数を 1 個の文字列で返す。
- `Dullmify.ask(prompt, input)`：`input` について LLM に `prompt` の判断を求め、答えの文字列を返す。
- `Dullmify.run_command(argv, stdin = "")`：シェルを介さず argv のコマンドを実行し、`{"exit_code"=>整数, "stdout"=>文字列, "stderr"=>文字列}` を返す。非 0 も通常の結果である。
- `Dullmify.read_file(path)`：ファイルの内容を返す。存在しなければ `nil` を返す。
- `Dullmify.write_file(path, content)`：親ディレクトリを作り、内容を書く。
- `Dullmify.fail(reason)`：workflow を failed で終了する。

`json` と `set` はランタイムが読み込み済みである。

## 規則

- LLM にしかできない判断だけを `ask` にし、ファイルの変更やコマンド実行を問いの文面で依頼しない。
- コマンド、ファイルの読み書き、引数、失敗は必ず上の API を通す。標準出力と標準エラーへ直接書かない。
- 時刻、乱数、環境変数など実行ごとに変わりうる値は、必要なら `run_command` で得る。
- `require` は書かない。ランタイムが読み込んだ標準ライブラリと Ruby の組み込み機能だけを使う。
- `exit`、`abort`、`exec`、プロセスを置き換える操作を使わない。
- `Exception`、`Object`、裸の rescue など、未回答の問いを示す合図まで捕まえる例外処理を書かない。捕捉するなら具体的な `StandardError` の派生型に限る。
- `ensure`、`at_exit`、ファイナライザなどの後始末から API を呼ばない。
- ソースの各工程に対応する箇所へ、節の見出しと工程番号をソースと同じ言語のコメントで付ける。
- API の実装や内部状態へアクセスせず、再実行を回避する仕掛けを作らない。
