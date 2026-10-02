#include "runtime.hpp"

std::string workflow() {
  dullmify::arguments();
  return std::string("a\xFF" "b", 3);
}
