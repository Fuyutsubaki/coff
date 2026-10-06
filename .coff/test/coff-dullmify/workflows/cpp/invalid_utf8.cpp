#include "runtime.hpp"

std::string workflow(const std::string &arguments) {
  return std::string("a\xFF" "b", 3);
}
