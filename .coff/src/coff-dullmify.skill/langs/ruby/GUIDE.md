# Ruby workflow ガイド

workflow は `workflow.rb` に書き、引数なしの `workflow` メソッドを定義する。戻り値は report の文字列にする。`runtime.rb` は `json` と `set` を読み込み済みである。

## API

- `Dullmify.arguments` は skill の引数を一つの文字列で返す。
- `Dullmify.ask(prompt, input = "")` は LLM にだけできる判断を問い、自由な文字列の答えを返す。形式が違う答えは workflow で判定し、理由を含む別の問いで問い直す。
- `Dullmify.once(key) { ... }` は観測を一度だけ行い、JSON にできる結果を記録して返す。
- `Dullmify.effect(key) { ... }` は世界を変える操作を一度だけ行う。実行前に予約を記録するため、途中で止まった run は再実行せず failed になる。
- `Dullmify.fail(reason)` は failed で終了する。`Kernel#fail` は使わない。
- `Dullmify.now`、`Dullmify.random(n)`、`Dullmify.env(name)`、`Dullmify.read(path)` は `once` 上の便利関数である。`now` は UTC の ISO 8601、`random` は n バイトの十六進文字列を返す。存在しない環境変数とファイルは `nil` を返す。
- `Dullmify.write(path, content)` と `Dullmify.command(argv, stdin = "")` は `effect` 上の便利関数である。`write` は親ディレクトリも作る。`command` はシェルを通さず、`{"exit_code", "stdout", "stderr"}` の文字列キーの Hash を返す。

## 規則

- workflow の制御は、`Dullmify.arguments` と補助関数が返した値だけで決める。
- 時刻、乱数、環境変数、ファイルの読み込みなどの観測は `once`、ファイルの書き込みとコマンド実行など世界を変える操作は `effect` の中だけで行う。できる限り便利関数を使う。
- `once` の中では世界を変えない。`once` と `effect` のブロック内から、`fail` 以外の補助関数を呼ばない。
- stdout と stderr に直接書かない。`puts`、`print`、`warn`、`p` を使わない。
- workflow の外のグローバル変数や定数に、呼び出しごとに変わる状態を持たせない。
- 問いと `fail` の中断を捕まえない。`rescue Exception` を使わず、補助関数を後始末の `ensure` から呼ばない。
- `exit`、`abort`、`exec` などでプロセスを終了しない。
- 標準ライブラリを追加で使う場合も、`json`、`set`、`time`、`securerandom`、`open3`、`fileutils` だけにする。外部 gem を使わない。
- workflow は再実行される。引数と記録が同じなら、補助関数の呼び出し順、キー、問い、report が同じになるようにする。
