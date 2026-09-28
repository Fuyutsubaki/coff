#include "runtime.hpp"

std::string workflow() {
    dullmify::arguments();
    return std::string("不正:") + std::string("\xFF", 1);
}
