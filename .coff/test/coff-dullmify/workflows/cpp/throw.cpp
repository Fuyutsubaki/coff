#include "runtime.hpp"

std::string workflow() {
  dullmify::arguments();
  throw std::runtime_error("意図した例外");
}
