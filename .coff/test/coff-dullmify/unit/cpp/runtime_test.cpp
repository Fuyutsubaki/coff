#define DULLMIFY_NO_MAIN
#include "runtime.hpp"

#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include "doctest.h"

namespace {

// テストごとに空の run ディレクトリを用意し、終わったら消す。
struct RuntimeFixture {
    RuntimeFixture() {
        directory = std::filesystem::temp_directory_path() /
                    ("coff-dullmify-unit-" + std::to_string(::getpid()) + "-" + std::to_string(counter++));
        std::filesystem::create_directories(directory);
        std::ofstream(directory / "workflow-key") << "キー";
    }

    ~RuntimeFixture() {
        std::error_code ignored;
        std::filesystem::remove_all(directory, ignored);
    }

    std::filesystem::path directory;
    static inline int counter = 0;
};

TEST_CASE_FIXTURE(RuntimeFixture, "問いの記録を書いて読み戻す") {
    dullmify::Runtime runtime(directory, "キー");
    CHECK_THROWS_AS(runtime.ask("判断", "対象"), dullmify::Pending);
    REQUIRE(runtime.records().size() == 1U);

    std::ofstream(directory / "answer") << "回答\n";
    dullmify::Runtime replay(directory, "キー");
    replay.prepare();
    CHECK(replay.ask("判断", "対象") == "回答");
    CHECK_NOTHROW(replay.finish());
    CHECK_FALSE(std::filesystem::exists(directory / "answer"));
}

TEST_CASE_FIXTURE(RuntimeFixture, "照合キーの食い違いを検出する") {
    dullmify::Runtime runtime(directory, "キー");
    CHECK_THROWS_AS(runtime.ask("判断", "対象"), dullmify::Pending);

    dullmify::Runtime replay(directory, "キー");
    CHECK_THROWS_AS(replay.ask("別の判断", "対象"), dullmify::Nondeterminism);
}

TEST_CASE_FIXTURE(RuntimeFixture, "壊れた記録を拒否する") {
    std::ofstream(directory / "records.jsonl") << "{壊れた記録\n";
    CHECK_THROWS_AS(dullmify::Runtime(directory, "キー"), dullmify::Failure);
}

TEST_CASE("不正な UTF-8 を正しい JSON にする") {
    const std::string text = dullmify::json_text({{"値", std::string("\xFF", 1)}});
    const auto parsed = dullmify::json::parse(text);
    CHECK(parsed.at("値").get<std::string>() == "\xEF\xBF\xBD");
}

}  // namespace
