#include "runtime.hpp"
#include <stdexcept>

std::string workflow() {
  dullmify::ask("Q", "");
  throw std::runtime_error("boom");
}
