// Test workflow with a slow command between two questions, to be killed midway.
#include "runtime.hpp"
std::string workflow() {
  std::string a = dullmify::ask("Q", "");
  dullmify::run_command({"sleep", "2"});
  std::string b = dullmify::ask("R", a);
  return a + "|" + b;
}
