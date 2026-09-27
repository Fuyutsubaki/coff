#include "runtime.hpp"
std::string workflow() {
  try {
    return dullmify::ask("q");
  } catch (...) {
    return "swallowed";
  }
}
