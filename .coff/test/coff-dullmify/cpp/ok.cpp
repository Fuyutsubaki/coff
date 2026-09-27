// Test workflow: two questions, one command, one write, one read, one missing read.
#include "runtime.hpp"
#include <string>

static std::string strip(std::string s) {
  while (!s.empty() && (s.back() == '\n' || s.back() == ' ')) s.pop_back();
  return s;
}

std::string workflow() {
  std::string a = dullmify::ask("first question", dullmify::args());
  dullmify::CommandResult r = dullmify::run_command({"sh", "-c", "echo x >> counter; echo out; echo err >&2"});
  dullmify::write_file("out/answer.txt", a);
  std::string b = dullmify::ask("second question", dullmify::read_file("out/answer.txt").value_or(""));
  return "report: " + a + "|" + b + "|" + std::to_string(r.status) + "|" + strip(r.out) + "|" + strip(r.err) + "|" +
         (dullmify::read_file("missing") ? "false" : "true");
}
