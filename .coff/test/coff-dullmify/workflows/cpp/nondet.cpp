#include "runtime.hpp"

#include <chrono>

std::string workflow() {
  const auto value = std::chrono::steady_clock::now().time_since_epoch().count();
  return dullmify::ask("時刻 " + std::to_string(value), dullmify::arguments());
}
