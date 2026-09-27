#include "runtime.hpp"
std::string workflow() {
  return dullmify::detail::state().run_dir;
}
