#include "runtime.hpp"

#include <chrono>
#include <thread>

std::string workflow(const std::string &arguments) {
  const std::string first = dullmify::ask("最初の問い", "一");
  std::this_thread::sleep_for(std::chrono::seconds(5));
  const std::string second = dullmify::ask("次の問い", first);
  return first + "|" + second;
}
