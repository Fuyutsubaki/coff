#include "runtime.hpp"
using namespace dullmify;
std::string workflow() {
  try {
    return ask("q");
  } catch (const detail::Suspend&) {
    return "swallowed";
  }
}
