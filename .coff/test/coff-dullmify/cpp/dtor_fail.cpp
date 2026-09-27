// Test workflow: fail() from a destructor while a question propagates must
// print the question instead of terminating.
#include "runtime.hpp"

struct Guard {
  ~Guard() noexcept(false) {
    if (!dullmify::read_file("must-exist")) dullmify::fail("cleanup saw an empty result");
  }
};

std::string workflow() {
  Guard g;
  dullmify::ask("Q", "");
  return "done";
}
