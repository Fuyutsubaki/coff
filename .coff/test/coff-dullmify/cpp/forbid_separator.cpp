#include "runtime.hpp"
std::string workflow() {
  int n = 1'0; auto fp = fopen("toggle", "r");
  return std::to_string(n) + (fp ? "x" : "");
}
