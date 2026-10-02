#include "runtime.hpp"

#include <chrono>
#include <thread>

std::string workflow() {
  dullmify::arguments();
  dullmify::effect(dullmify::json::array({"遅い副作用"}), [] {
    std::this_thread::sleep_for(std::chrono::seconds(5));
    return std::string("完了");
  });
  return "完了";
}
