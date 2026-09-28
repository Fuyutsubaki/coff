#include "runtime.hpp"

std::string workflow() {
    dullmify::arguments();
    if (std::filesystem::exists("nondet.flag")) {
        dullmify::ask("変更後の問い", "A");
    } else {
        std::ofstream output("nondet.flag");
        output << "作成";
        output.close();
        dullmify::ask("最初の問い", "B");
    }
    return "到達しない";
}
