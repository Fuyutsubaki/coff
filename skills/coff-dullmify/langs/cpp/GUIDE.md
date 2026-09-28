# C++ workflow ガイド

workflow のファイル名は `workflow.cpp` とする。先頭で `#include "runtime.hpp"` と書き、引数を取らない `std::string workflow()` を定義する。戻り値が最終的な report になる。C++17 と `<filesystem>` を追加のリンク指定なしで使える環境を対象にする。

## API

- `dullmify::arguments()`：skill に渡された引数を 1 個の `std::string` で返す。
- `dullmify::ask(prompt, input)`：`input` について LLM に `prompt` の判断を求め、答えの文字列を返す。
- `dullmify::run_command(argv, stdin = "")`：シェルを介さず `std::vector<std::string>` の argv を実行し、`exit_code`、`stdout`、`stderr` を持つ `nlohmann::json` を返す。非 0 も通常の結果である。
- `dullmify::read_file(path)`：`std::optional<std::string>` で内容を返す。存在しなければ `std::nullopt` である。
- `dullmify::write_file(path, content)`：親ディレクトリを作り、内容を書く。
- `dullmify::fail(reason)`：workflow を failed で終了する。

`runtime.hpp` から標準ライブラリと `nlohmann::json` を利用できる。

## 規則

- LLM にしかできない判断だけを `ask` にし、ファイルの変更やコマンド実行を問いの文面で依頼しない。
- コマンド、ファイルの読み書き、引数、失敗は必ず上の API を通す。標準出力と標準エラーへ直接書かない。
- 時刻、乱数、環境変数など実行ごとに変わりうる値は、必要なら `run_command` で得る。
- `#include` は `runtime.hpp` だけにする。ランタイムが提供する標準ライブラリと nlohmann/json 以外を使わない。
- `exit`、`abort`、`exec`、プロセスを置き換える操作を使わない。
- `catch (...)` や例外でない値の捕捉など、未回答の問いを示す合図まで捕まえる例外処理を書かない。
- デストラクタなどの後始末から API を呼ばない。
- ソースの各工程に対応する箇所へ、節の見出しと工程番号をソースと同じ言語のコメントで付ける。
- API の実装や内部状態へアクセスせず、再実行を回避する仕掛けを作らない。
