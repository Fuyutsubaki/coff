#include "runtime.hpp"
std::string workflow() {
  auto f = &std::fopen;
  return f ? "r" : "";
}
