#ifndef COFF_DULLMIFY_RUNTIME_HPP
#define COFF_DULLMIFY_RUNTIME_HPP

#include "json.hpp"

#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <map>
#include <optional>
#include <stdexcept>
#include <string>
#include <system_error>
#include <utility>
#include <vector>

#include <fcntl.h>
#include <sys/wait.h>
#include <unistd.h>

namespace dullmify {

using json = nlohmann::json;

// 未回答の問いを外側のランタイムまで運ぶ。std::exception は継承しない。
struct Pending {
    json record;
};

class Failure : public std::runtime_error {
  public:
    using std::runtime_error::runtime_error;
};

class Nondeterminism : public std::runtime_error {
  public:
    using std::runtime_error::runtime_error;
};

inline std::string read_binary(const std::filesystem::path& path) {
    std::ifstream input(path, std::ios::binary);
    if (!input) {
        throw Failure("ファイルを読めません: " + path.string());
    }
    return std::string(std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>());
}

inline std::string trim_one_newline(std::string value) {
    if (value.size() >= 2 && value.compare(value.size() - 2, 2, "\r\n") == 0) {
        value.resize(value.size() - 2);
    } else if (!value.empty() && value.back() == '\n') {
        value.pop_back();
    }
    return value;
}

inline std::string json_text(const json& value) {
    return value.dump(-1, ' ', false, json::error_handler_t::replace);
}

inline std::string errno_message(const std::string& operation) {
    return operation + ": " + std::strerror(errno);
}

struct CommandResult {
    int exit_code;
    std::string standard_output;
    std::string standard_error;

    json to_json() const {
        return {
            {"exit_code", exit_code},
            {"stdout", standard_output},
            {"stderr", standard_error},
        };
    }
};

// 一時ファイルを使って子プロセスの三つのストリームを分離する。
class TemporaryFile {
  public:
    explicit TemporaryFile(const std::filesystem::path& run_dir) {
        std::string pattern = (run_dir / ".command.XXXXXX").string();
        std::vector<char> writable(pattern.begin(), pattern.end());
        writable.push_back('\0');
        descriptor_ = ::mkstemp(writable.data());
        if (descriptor_ < 0) {
            throw Failure(errno_message("コマンド用の一時ファイルを作成できません"));
        }
        path_ = writable.data();
        ::unlink(path_.c_str());
    }

    TemporaryFile(const TemporaryFile&) = delete;
    TemporaryFile& operator=(const TemporaryFile&) = delete;

    ~TemporaryFile() {
        if (descriptor_ >= 0) {
            ::close(descriptor_);
        }
    }

    int descriptor() const { return descriptor_; }

    void rewind_file() {
        if (::lseek(descriptor_, 0, SEEK_SET) < 0) {
            throw Failure(errno_message("一時ファイルを巻き戻せません"));
        }
    }

    void truncate_file() {
        if (::ftruncate(descriptor_, 0) < 0) {
            throw Failure(errno_message("一時ファイルを空にできません"));
        }
        rewind_file();
    }

    void write_all(const std::string& content) {
        const char* cursor = content.data();
        std::size_t remaining = content.size();
        while (remaining > 0) {
            const ssize_t written = ::write(descriptor_, cursor, remaining);
            if (written < 0) {
                if (errno == EINTR) continue;
                throw Failure(errno_message("一時ファイルに書けません"));
            }
            cursor += written;
            remaining -= static_cast<std::size_t>(written);
        }
    }

    std::string read_all() {
        rewind_file();
        std::string content;
        char buffer[8192];
        for (;;) {
            const ssize_t count = ::read(descriptor_, buffer, sizeof(buffer));
            if (count == 0) break;
            if (count < 0) {
                if (errno == EINTR) continue;
                throw Failure(errno_message("一時ファイルを読めません"));
            }
            content.append(buffer, static_cast<std::size_t>(count));
        }
        return content;
    }

  private:
    int descriptor_ = -1;
    std::string path_;
};

class Runtime {
  public:
    Runtime(std::filesystem::path run_dir, std::string workflow_key)
        : run_dir_(std::filesystem::absolute(std::move(run_dir))),
          workflow_key_(std::move(workflow_key)),
          records_path_(run_dir_ / "records.jsonl") {
        load_records();
    }

    void prepare() {
        const std::string expected = read_binary(run_dir_ / "workflow-key");
        if (expected != workflow_key_) {
            throw Nondeterminism("workflow またはランタイムが実行途中で変更されました");
        }

        const auto answer_path = run_dir_ / "answer";
        if (!std::filesystem::is_regular_file(answer_path)) return;

        auto pending = records_.end();
        for (auto iterator = records_.begin(); iterator != records_.end(); ++iterator) {
            if ((*iterator).value("type", "") == "ask" && !iterator->contains("result")) {
                pending = iterator;
                break;
            }
        }
        if (pending == records_.end()) {
            throw Nondeterminism("回答の対象になる問いが記録にありません");
        }
        (*pending)["result"] = trim_one_newline(read_binary(answer_path));
        save_records();
        std::filesystem::remove(answer_path);
    }

    std::string arguments() const {
        const auto path = run_dir_ / "args";
        if (!std::filesystem::is_regular_file(path)) {
            throw Failure("引数ファイルがありません");
        }
        return trim_one_newline(read_binary(path));
    }

    std::string ask(const std::string& prompt, const std::string& input) {
        const json key = {{"prompt", prompt}, {"input", input}};
        json& record = consume("ask", key, [&] {
            return append_record({{"type", "ask"}, {"key", key}});
        });
        if (!record.contains("result")) {
            throw Pending{record};
        }
        return record.at("result").get<std::string>();
    }

    json run_command(const std::vector<std::string>& argv, const std::string& input = "") {
        if (argv.empty()) throw Failure("コマンドの argv が空です");
        const json key = {{"argv", argv}, {"stdin", input}};
        json& record = consume("command", key, [&] {
            return append_record({
                {"type", "command"},
                {"key", key},
                {"result", execute_command(argv, input).to_json()},
            });
        });
        return record.at("result");
    }

    std::optional<std::string> read_file(const std::string& path) {
        const json key = {{"path", path}};
        json& record = consume("read", key, [&] {
            json result = nullptr;
            if (std::filesystem::is_regular_file(path)) result = read_binary(path);
            return append_record({{"type", "read"}, {"key", key}, {"result", result}});
        });
        if (record.at("result").is_null()) return std::nullopt;
        return record.at("result").get<std::string>();
    }

    bool write_file(const std::string& path, const std::string& content) {
        const json key = {{"path", path}, {"content", content}};
        json& record = consume("write", key, [&] {
            const std::filesystem::path target(path);
            if (target.has_parent_path()) std::filesystem::create_directories(target.parent_path());
            std::ofstream output(target, std::ios::binary | std::ios::trunc);
            if (!output) throw Failure("ファイルを開けません: " + path);
            output.write(content.data(), static_cast<std::streamsize>(content.size()));
            if (!output) throw Failure("ファイルを書けません: " + path);
            output.close();
            return append_record({{"type", "write"}, {"key", key}, {"result", true}});
        });
        return record.at("result").get<bool>();
    }

    [[noreturn]] void fail(const std::string& reason) { throw Failure(reason); }

    void finish() const {
        if (cursor_ != records_.size()) {
            throw Nondeterminism("記録をすべて消費せずに workflow が終了しました");
        }
    }

    const std::filesystem::path& run_dir() const { return run_dir_; }
    const std::vector<json>& records() const { return records_; }
    std::size_t cursor() const { return cursor_; }

    void save_records() const {
        const auto temporary = run_dir_ / (".records." + std::to_string(::getpid()) + ".tmp");
        try {
            std::ofstream output(temporary, std::ios::binary | std::ios::trunc);
            if (!output) throw Failure("記録の一時ファイルを開けません");
            for (const auto& record : records_) output << json_text(record) << '\n';
            output.close();
            if (!output) throw Failure("記録の一時ファイルを書けません");
            std::filesystem::rename(temporary, records_path_);
        } catch (...) {
            std::error_code ignored;
            std::filesystem::remove(temporary, ignored);
            throw;
        }
    }

  private:
    template <typename Action>
    json& consume(const std::string& type, const json& key, Action action) {
        if (cursor_ < records_.size()) {
            json& record = records_[cursor_];
            if (record.value("type", "") != type || !record.contains("key") || record["key"] != key) {
                throw Nondeterminism("記録と今回の実行が一致しません（" + type + "）");
            }
            ++cursor_;
            return record;
        }
        action();
        ++cursor_;
        return records_.back();
    }

    json& append_record(json record) {
        records_.push_back(std::move(record));
        std::ofstream output(records_path_, std::ios::binary | std::ios::app);
        if (!output) throw Failure("記録を開けません");
        output << json_text(records_.back()) << '\n';
        output.close();
        if (!output) throw Failure("記録を書けません");
        return records_.back();
    }

    void load_records() {
        if (!std::filesystem::exists(records_path_)) return;
        std::ifstream input(records_path_, std::ios::binary);
        if (!input) throw Failure("記録を読めません");
        std::string line;
        try {
            while (std::getline(input, line)) {
                if (!line.empty()) records_.push_back(json::parse(line));
            }
        } catch (const std::exception& error) {
            throw Failure(std::string("記録を読めません: ") + error.what());
        }
        if (!input.eof()) throw Failure("記録を読めません");
    }

    CommandResult execute_command(const std::vector<std::string>& argv, const std::string& input) {
        TemporaryFile standard_input(run_dir_);
        TemporaryFile standard_output(run_dir_);
        TemporaryFile standard_error(run_dir_);
        standard_input.write_all(input);
        standard_input.rewind_file();
        standard_output.truncate_file();
        standard_error.truncate_file();

        const pid_t child = ::fork();
        if (child < 0) throw Failure(errno_message("コマンドを起動できません"));
        if (child == 0) {
            if (::dup2(standard_input.descriptor(), STDIN_FILENO) < 0 ||
                ::dup2(standard_output.descriptor(), STDOUT_FILENO) < 0 ||
                ::dup2(standard_error.descriptor(), STDERR_FILENO) < 0) {
                _exit(126);
            }
            std::vector<char*> values;
            values.reserve(argv.size() + 1);
            for (const auto& value : argv) values.push_back(const_cast<char*>(value.c_str()));
            values.push_back(nullptr);
            ::execvp(values[0], values.data());
            _exit(127);
        }

        int status = 0;
        while (::waitpid(child, &status, 0) < 0) {
            if (errno == EINTR) continue;
            throw Failure(errno_message("コマンドの終了を待てません"));
        }
        int exit_code = 125;
        if (WIFEXITED(status)) exit_code = WEXITSTATUS(status);
        else if (WIFSIGNALED(status)) exit_code = 128 + WTERMSIG(status);

        return {exit_code, standard_output.read_all(), standard_error.read_all()};
    }

    std::filesystem::path run_dir_;
    std::string workflow_key_;
    std::filesystem::path records_path_;
    std::vector<json> records_;
    std::size_t cursor_ = 0;
};

inline Runtime* current_runtime = nullptr;

inline Runtime& runtime() {
    if (!current_runtime) throw Failure("ランタイムが初期化されていません");
    return *current_runtime;
}

inline std::string arguments() { return runtime().arguments(); }
inline std::string ask(const std::string& prompt, const std::string& input) { return runtime().ask(prompt, input); }
inline json run_command(const std::vector<std::string>& argv, const std::string& input = "") {
    return runtime().run_command(argv, input);
}
inline std::optional<std::string> read_file(const std::string& path) { return runtime().read_file(path); }
inline bool write_file(const std::string& path, const std::string& content) { return runtime().write_file(path, content); }
[[noreturn]] inline void fail(const std::string& reason) { runtime().fail(reason); }

inline void emit(const json& value) { std::cout << json_text(value) << std::endl; }

inline void remove_run(const std::filesystem::path& run_dir) {
    std::error_code ignored;
    std::filesystem::remove_all(run_dir, ignored);
}

}  // dullmify 名前空間

#ifndef DULLMIFY_NO_MAIN
std::string workflow();

int main(int argc, char** argv) {
    if (argc != 3) {
        std::cerr << "ランタイムの引数が正しくありません" << std::endl;
        return 2;
    }

    if (std::string(argv[1]) == "--start") {
        const std::filesystem::path run_dir = std::filesystem::absolute(argv[2]);
        dullmify::emit({{"run", run_dir.string()}, {"write", (run_dir / "args").string()}});
        return 0;
    }

    const std::filesystem::path run_dir = std::filesystem::absolute(argv[1]);
    try {
        if (!std::filesystem::is_regular_file(run_dir / "args")) {
            dullmify::emit({{"run", run_dir.string()}, {"write", (run_dir / "args").string()}});
            return 0;
        }
        dullmify::Runtime runtime(run_dir, argv[2]);
        dullmify::current_runtime = &runtime;
        runtime.prepare();
        const std::string cwd = dullmify::trim_one_newline(dullmify::read_binary(run_dir / "cwd"));
        std::filesystem::current_path(cwd);
        const std::string report = workflow();
        runtime.finish();
        dullmify::emit({{"done", true}, {"report", report}});
        dullmify::remove_run(run_dir);
    } catch (const dullmify::Pending& pending) {
        const auto& key = pending.record.at("key");
        dullmify::emit({
            {"run", run_dir.string()},
            {"prompt", key.at("prompt")},
            {"input", key.at("input")},
            {"write", (run_dir / "answer").string()},
        });
    } catch (const std::exception& error) {
        dullmify::emit({{"failed", error.what()}});
        dullmify::remove_run(run_dir);
    } catch (...) {
        dullmify::emit({{"failed", "workflow で種類不明の例外が発生しました"}});
        dullmify::remove_run(run_dir);
    }
    return 0;
}
#endif

#endif
