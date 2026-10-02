#include "runtime.hpp"

std::string workflow() {
  const std::string args = dullmify::arguments();
  const std::string first = dullmify::ask("最初の答えを一語で返してください", args);
  const std::string second = dullmify::ask("二番目の答えを一語で返してください", first);
  const auto result = dullmify::command({"tee", "-a", "effect.log"}, "一回\n");
  if (result.exit_code != 0) dullmify::fail("追記コマンドが失敗しました");
  return args + "|" + first + "|" + second;
}
