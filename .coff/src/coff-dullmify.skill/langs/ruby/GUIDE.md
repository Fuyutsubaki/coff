# Ruby workflow ガイド

workflow は `workflow.rb` に書き、skill の引数を一つの文字列で受け取る `workflow(arguments)` メソッドを定義する。戻り値は report の文字列にする。`runtime.rb` は `json` を読み込み済みである。

## API

- `Dullmify.ask(prompt, input = "")` は LLM にだけできる判断を問い、自由な文字列の答えを返す。形式が違う答えは workflow で判定し、理由を含む別の問いで問い直す。
- `Dullmify.once(key) { ... }` は観測（時刻、乱数、環境変数、ファイルの読み込みのように、実行ごとに変わりうる値を得ること）を一度だけ行い、JSON にできる結果を記録して返す。
- `Dullmify.effect(key) { ... }` は副作用（ファイルの書き込みやコマンドの実行のように、workflow の外に変化を残す操作）を一度だけ行う。実行前に結果のない記録（予約）を書き、途中で止まった run を続けると、副作用を二度行わずに failed にする。
- `Dullmify.fail(reason)` は failed で終了する。`Kernel#fail` は使わない。
- `Dullmify.now`、`Dullmify.random(n)`、`Dullmify.env(name)`、`Dullmify.read(path)` は `once` を使った便利関数である。`now` は UTC の ISO 8601、`random` は n バイトの十六進文字列を返す。存在しない環境変数とファイルは `nil` を返す。
- `Dullmify.write(path, content)` と `Dullmify.command(argv, stdin = "")` は `effect` を使った便利関数である。`write` は親ディレクトリも作る。`command` はシェルを通さず、`{"exit_code", "stdout", "stderr"}` の文字列キーの Hash を返す。

## 規則

- workflow の制御は、`arguments` と補助関数が返した値だけで決める。
- 時刻、乱数、環境変数、ファイルの読み込みなどの観測は `once`、副作用は `effect` の中だけで起こす。できる限り便利関数を使う。
- `once` の中で副作用を起こさない。`once` と `effect` のブロック内から、`fail` 以外の補助関数を呼ばない。
- stdout と stderr に直接書かない。`puts`、`print`、`warn`、`p` を使わない。
- workflow の外のグローバル変数や定数に、workflow の呼び出しをまたいで変わる状態を持たせない。
- `ask` と `fail` は workflow を途中で抜けて中断する。この中断を捕まえない。`rescue Exception` を使わず、補助関数を後始末の `ensure` から呼ばない。
- `exit`、`abort`、`exec` などでプロセスを終了しない。
- 標準ライブラリを追加で使う場合も、`json`、`set`、`time`、`securerandom`、`open3`、`fileutils` だけにする。外部 gem を使わない。
- workflow は再実行される。引数と記録が同じなら、補助関数の呼び出し順、キー、問い、report が同じになるようにする。
