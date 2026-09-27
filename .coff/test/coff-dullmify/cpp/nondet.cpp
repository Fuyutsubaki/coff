// Test workflow that bypasses the runtime on purpose (fopen) so its control
// flow changes between runs. Never passes check.
#include "runtime.hpp"
#include <cstdio>

std::string workflow() {
  std::string mode = dullmify::args();
  dullmify::ask("A", "");
  FILE* f = std::fopen("toggle", "r");
  if (f) {
    std::fclose(f);
    if (mode == "early") return "early";
    dullmify::ask("C", "");
  } else {
    dullmify::ask("B", "");
  }
  return "done";
}
