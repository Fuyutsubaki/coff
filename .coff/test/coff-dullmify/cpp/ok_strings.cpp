// system("ls") in a comment is fine, and so is std::cout here
#include "runtime.hpp"
#include <string>
/* fopen("x") getenv("HOME")
   #include <fstream> inside a block comment */
std::string workflow() {
  std::string note = "system(\"ls\") and std::cout and fopen( appear only in strings";
  char c = '"';
  std::string more = "exit(1) \\\" rand()";
  int big = 1'000'000; // digit separators are not char literals
  return note + c + more + std::to_string(big);
}
