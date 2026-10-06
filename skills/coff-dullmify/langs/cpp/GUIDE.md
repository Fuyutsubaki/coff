# C++ workflow ガイド

workflow は `workflow.cpp` に書き、先頭で `#include "runtime.hpp"` を読み込み、skill の引数を一つの文字列で受け取る `std::string workflow(const std::string &arguments)` を定義する。C++17 を使う。

## API

すべて `dullmify` 名前空間にある。`dullmify::detail` は内部実装なので使わない。

- `ask(prompt, input = "")` は LLM にだけできる判断を問い、自由な文字列の答えを返す。形式が違う答えは workflow で判定し、理由を含む別の問いで問い直す。
- `once(key, [] { ... })` は観測（時刻、乱数、環境変数、ファイルの読み込みのように、実行ごとに変わりうる値を得ること）を一度だけ行う。`effect(key, [] { ... })` は副作用（ファイルの書き込みやコマンドの実行のように、workflow の外に変化を残す操作）を一度だけ行う。実行前に結果のない記録（予約）を書き、途中で止まった run を続けると、副作用を二度行わずに failed にする。キーと戻り値は `nlohmann::json` と相互に変換できる型にする。
- `fail(reason)` は failed で終了する。
- `now()`、`random(n)`、`env(name)`、`read(path)` は `once` を使った便利関数である。`now` は UTC の ISO 8601、`random` は n バイトの十六進文字列を返す。存在しない環境変数とファイルは `std::nullopt` を返す。
- `write(path, content)` と `command(argv, stdin = "")` は `effect` を使った便利関数である。`write` は親ディレクトリも作る。`command` はシェルを通さず、`CommandResult` の `exit_code`、`stdout_text`、`stderr_text` を返す。
- JSON データには同梱の `nlohmann::json` を使える。

## 規則

- workflow の制御は、`arguments` と補助関数が返した値だけで決める。
- 時刻、乱数、環境変数、ファイルの読み込みなどの観測は `once`、副作用は `effect` の中だけで起こす。できる限り便利関数を使う。
- `once` の中で副作用を起こさない。`once` と `effect` のブロック内から、`fail` 以外の補助関数を呼ばない。
- stdout と stderr に直接書かない。`std::cout`、`std::cerr`、`printf` を使わない。
- workflow の外のグローバル変数や `static` に、workflow の呼び出しをまたいで変わる状態を持たせない。
- `ask` と `fail` は workflow を途中で抜けて中断する。この中断を捕まえない。`catch (...)` を使わず、デストラクタから補助関数を呼ばない。
- `exit`、`abort`、`_Exit` などでプロセスを終了しない。
- include は C++17 標準ライブラリ、`runtime.hpp`、`json.hpp` だけにする。別のライブラリを使わない。
- workflow は再実行される。引数と記録が同じなら、補助関数の呼び出し順、キー、問い、report が同じになるようにする。
