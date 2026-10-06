#include "runtime.hpp"

#include <map>
#include <string>
#include <vector>

std::string workflow(const std::string &arguments) {
  // 都道府県と地域の確認 / 手順 1
  const std::string input = arguments;
  const std::size_t separator = input.find("、");
  if (separator == std::string::npos || input.find("、", separator + 3) != std::string::npos)
    dullmify::fail("市名を二つ指定してください");
  const std::vector<std::string> cities{input.substr(0, separator), input.substr(separator + 3)};

  // 都道府県と地域の確認 / 手順 2
  std::vector<std::string> prefectures;
  for (const auto &city : cities) {
    std::string answer;
    bool valid = false;
    for (int attempt = 0; attempt < 4; ++attempt) {
      const std::string prompt =
          attempt == 0 ? std::string("都道府県名だけを答えてください")
                       : "前の答え「" + answer + "」は末尾が都、道、府、県のいずれでもありません。都道府県名だけを、末尾まで含めて答え直してください";
      answer = dullmify::ask(prompt, city);
      const std::vector<std::string> suffixes{"都", "道", "府", "県"};
      for (const auto &suffix : suffixes)
        if (answer.size() >= suffix.size() && answer.compare(answer.size() - suffix.size(), suffix.size(), suffix) == 0)
          valid = true;
      if (valid) break;
    }
    if (!valid) dullmify::fail("都道府県名の形式が不正です");
    prefectures.push_back(answer);
  }

  // 都道府県と地域の確認 / 手順 3
  const std::map<std::string, std::string> region_by_prefecture{{"神奈川県", "関東"}, {"宮城県", "東北"}};
  std::vector<std::string> regions;
  for (const auto &prefecture : prefectures) {
    const auto found = region_by_prefecture.find(prefecture);
    if (found == region_by_prefecture.end()) dullmify::fail("地域の辞書にない都道府県です: " + prefecture);
    regions.push_back(found->second);
  }

  // 都道府県と地域の確認 / 手順 4
  const std::string report = cities[0] + "=" + prefectures[0] + "(" + regions[0] + "), " +
                             cities[1] + "=" + prefectures[1] + "(" + regions[1] + ")";

  // 都道府県と地域の確認 / 手順 5
  const auto command_result = dullmify::command({"printf", "%s", report});
  if (command_result.exit_code != 0) dullmify::fail("printf が失敗しました");

  // 都道府県と地域の確認 / 手順 6
  dullmify::write("prefecture-output.txt", command_result.stdout_text);
  return command_result.stdout_text;
}
