#include "runtime.hpp"

#include <chrono>

std::string workflow(const std::string &arguments) {
  dullmify::ask("確認してください", arguments);
  const auto value = std::chrono::steady_clock::now().time_since_epoch().count();
  return "時刻 " + std::to_string(value);
}
