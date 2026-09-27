#include "runtime.hpp"
extern "C" char** __environ;
std::string workflow() {
  return __environ[0];
}
