#include "runtime.hpp"

#include <chrono>

std::string workflow() {
  dullmify::ask("確認してください", dullmify::arguments());
  const auto value = std::chrono::steady_clock::now().time_since_epoch().count();
  return "時刻 " + std::to_string(value);
}
