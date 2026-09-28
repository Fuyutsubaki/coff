#include "runtime.hpp"

std::string workflow() {
    // 都道府県コードを作る 1. 住所を入力順に得る
    std::vector<std::string> addresses;
    std::string input = dullmify::arguments();
    std::size_t start = 0;
    while (start < input.size()) {
        const auto end = input.find('\n', start);
        const std::string line = input.substr(start, end - start);
        if (!line.empty()) addresses.push_back(line);
        if (end == std::string::npos) break;
        start = end + 1;
    }
    std::vector<std::string> prefectures;
    for (const auto& address : addresses) {
        // 都道府県コードを作る 2. 市区町村を尋ねる
        const auto city = dullmify::ask("住所から市区町村名だけを答えてください", address);
        // 都道府県コードを作る 3. 都道府県を尋ねる
        prefectures.push_back(dullmify::ask("市区町村が属する都道府県名を末尾まで含めて答えてください", city));
    }
    std::vector<std::string> results;
    for (const auto& prefecture : prefectures) {
        // 都道府県コードを作る 4. 辞書でコードにする
        const std::map<std::string, std::string> codes{{"東京都", "13"}, {"大阪府", "27"}};
        const auto found = codes.find(prefecture);
        if (found == codes.end()) dullmify::fail("対応していない都道府県です: " + prefecture);
        // 都道府県コードを作る 5. printf でコードを得る
        const auto command = dullmify::run_command({"printf", "%s", found->second});
        if (command.at("exit_code").get<int>() != 0) dullmify::fail("printf が失敗しました");
        results.push_back(prefecture + "=" + command.at("stdout").get<std::string>());
    }
    // 都道府県コードを作る 6. 結果をファイルへ書く
    std::string content;
    for (std::size_t index = 0; index < results.size(); ++index) content += (index ? ", " : "") + results[index];
    dullmify::write_file("prefecture-result.txt", content);
    // 都道府県コードを作る 7. report を返す
    return "処理完了: " + content;
}
