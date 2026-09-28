#include "runtime.hpp"

std::string workflow() {
    // 基本動作 1. 引数を読む
    const std::string argument = dullmify::arguments();

    // 基本動作 2. 最初の判断を尋ねる
    const std::string first = dullmify::ask("最初の値を答えてください", argument);

    // 基本動作 3. コマンドを一度だけ実行する
    const auto command = dullmify::run_command({"sh", "-c", "printf '実行済み\\n' >> side-effect.log"});
    if (command.at("exit_code").get<int>() != 0) dullmify::fail("コマンドが失敗しました");

    // 基本動作 4. 未作成のファイルを読み、結果を書く
    const auto previous = dullmify::read_file("not-created.txt");
    dullmify::write_file("result.txt", first + "|" + (previous ? *previous : "なし"));

    // 基本動作 5. 二つ目の判断を尋ねる
    const std::string second = dullmify::ask("二つ目の値を答えてください", first);

    // 基本動作 6. report を返す
    return "完了: " + first + "/" + second;
}
