#include "runtime.hpp"

std::string workflow() {
    dullmify::arguments();
    throw std::runtime_error("テスト用の例外");
}
