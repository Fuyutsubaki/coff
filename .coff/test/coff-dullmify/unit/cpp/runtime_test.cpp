#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#define DULLMIFY_NO_MAIN
#include "doctest.h"
#include "../../../../src/coff-dullmify.skill/langs/cpp/runtime.hpp"

#include <filesystem>
#include <fstream>
#include <map>

std::string workflow(const std::string &) { return "単体テスト"; }

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

TEST_CASE("command はシェルを通さず、終了コードと出力を返す") {
  TemporaryDirectory temporary;
  dullmify::detail::Runtime state(temporary.path);
  dullmify::detail::current_runtime = &state;
  CHECK(dullmify::command({"echo $HOME"}).exit_code == 127);
  CHECK(dullmify::command({"echo", "$HOME"}).stdout_text == "$HOME\n");
  CHECK(dullmify::command({}).exit_code == 127);
  const auto piped = dullmify::command({"sh", "-c", "cat; echo err >&2; exit 3"}, "入力");
  CHECK(piped.exit_code == 3);
  CHECK(piped.stdout_text == "入力");
  CHECK(piped.stderr_text == "err\n");
  CHECK(dullmify::command({"sh", "-c", "kill -TERM $$"}).exit_code == 128 + SIGTERM);
  // SIGCHLD を無視する親から起動されても、終了コードを取れる。
  std::signal(SIGCHLD, SIG_IGN);
  CHECK(dullmify::command({"false"}).exit_code == 1);
  std::signal(SIGCHLD, SIG_DFL);
  CHECK_FALSE(fs::exists(temporary.path / ".command-stdout"));
  dullmify::detail::current_runtime = nullptr;
}

TEST_CASE("ディレクトリを read すると failed になる") {
  TemporaryDirectory temporary;
  dullmify::detail::Runtime state(temporary.path);
  dullmify::detail::current_runtime = &state;
  CHECK_THROWS_AS(dullmify::read(temporary.path), dullmify::detail::Failure);
  dullmify::detail::current_runtime = nullptr;
}

TEST_CASE("初回も再実行も、JSON を通した同じ値を返す") {
  TemporaryDirectory temporary;
  const auto observe = [] {
    // 不正な UTF-8 は記録で置き換わるので、初回の値も置き換えた後のものになる。
    return std::map<std::string, std::string>{{"text", std::string("a\xFF" "b", 3)}};
  };
  dullmify::detail::Runtime first(temporary.path);
  dullmify::detail::current_runtime = &first;
  const auto initial = dullmify::once(dullmify::json::array({"map"}), observe);

  dullmify::detail::Runtime second(temporary.path);
  dullmify::detail::current_runtime = &second;
  const auto replayed = dullmify::once(dullmify::json::array({"map"}), observe);
  CHECK(initial.at("text") == "a�b");
  CHECK(initial == replayed);
  dullmify::detail::current_runtime = nullptr;
}
