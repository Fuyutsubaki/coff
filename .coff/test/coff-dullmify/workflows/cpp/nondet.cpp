#include "runtime.hpp"

#include <chrono>

std::string workflow(const std::string &arguments) {
  const auto value = std::chrono::steady_clock::now().time_since_epoch().count();
  return dullmify::ask("時刻 " + std::to_string(value), arguments);
}
