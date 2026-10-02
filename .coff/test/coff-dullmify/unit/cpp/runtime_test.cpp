#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#define DULLMIFY_NO_MAIN
#include "doctest.h"
#include "../../../../src/coff-dullmify.skill/langs/cpp/runtime.hpp"

#include <filesystem>
#include <fstream>

std::string workflow() { return "単体テスト"; }

namespace {

namespace fs = std::filesystem;

struct TemporaryDirectory {
  fs::path path;
  TemporaryDirectory() {
    std::string pattern = (fs::temp_directory_path() / "dullmify-cpp-unit-XXXXXX").string();
    std::vector<char> buffer(pattern.begin(), pattern.end());
    buffer.push_back('\0');
    path = ::mkdtemp(buffer.data());
    std::ofstream(path / "args") << "引数\n";
    std::ofstream(path / "cwd") << fs::current_path().string() << '\n';
  }
  ~TemporaryDirectory() { std::error_code ignored; fs::remove_all(path, ignored); }
};

}  // 無名名前空間

TEST_CASE("記録の書き込み、読み戻し、型の往復") {
  TemporaryDirectory temporary;
  dullmify::detail::Runtime first(temporary.path);
  dullmify::detail::current_runtime = &first;
  const std::string value = dullmify::once(dullmify::json::array({"key"}), [] { return std::string("value"); });
  CHECK(value == "value");
  CHECK(first.records().front().at("result") == "value");

  dullmify::detail::Runtime second(temporary.path);
  dullmify::detail::current_runtime = &second;
  int calls = 0;
  const std::string replayed = dullmify::once(dullmify::json::array({"key"}), [&] {
    ++calls;
    return std::string("other");
  });
  CHECK(replayed == "value");
  CHECK(calls == 0);
  dullmify::detail::current_runtime = nullptr;
}

TEST_CASE("照合キーの食い違いを検出する") {
  TemporaryDirectory temporary;
  dullmify::detail::Runtime first(temporary.path);
  dullmify::detail::current_runtime = &first;
  dullmify::once(dullmify::json::array({"a"}), [] { return 1; });
  dullmify::detail::Runtime second(temporary.path);
  dullmify::detail::current_runtime = &second;
  CHECK_THROWS_AS(dullmify::once(dullmify::json::array({"b"}), [] { return 2; }), dullmify::detail::Failure);
  dullmify::detail::current_runtime = nullptr;
}

TEST_CASE("不正な UTF-8 を JSON にできる") {
  const std::string invalid("a\xFF" "b", 3);
  const std::string encoded = dullmify::detail::dump_json(dullmify::json{{"value", invalid}});
  dullmify::json parsed;
  CHECK_NOTHROW(parsed = dullmify::json::parse(encoded));
  CHECK(parsed.at("value") == "a�b");
}
