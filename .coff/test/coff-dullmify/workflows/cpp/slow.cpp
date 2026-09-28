#include "runtime.hpp"

std::string workflow() {
    dullmify::arguments();
    const std::string first = dullmify::ask("停止前の問い", "一つ目");
    ::sleep(2);
    const std::string second = dullmify::ask("再開後の問い", first);
    return "再開: " + second;
}
