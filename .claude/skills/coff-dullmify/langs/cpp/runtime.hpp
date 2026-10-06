#ifndef COFF_DULLMIFY_RUNTIME_HPP
#define COFF_DULLMIFY_RUNTIME_HPP

#include "json.hpp"

#include <cerrno>
#include <csignal>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iomanip>
#include <iostream>
#include <optional>
#include <random>
#include <sstream>
#include <stdexcept>
#include <string>
#include <type_traits>
#include <utility>
#include <vector>

#include <fcntl.h>
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

std::string workflow(const std::string &arguments);

namespace dullmify {

using json = nlohmann::json;
namespace fs = std::filesystem;

struct CommandResult {
  int exit_code;
  std::string stdout_text;
  std::string stderr_text;

  // effect が結果を記録に書くときと記録から読み戻すときに、nlohmann/json が ADL で見つけて呼ぶ。
  // 利用者は直接呼ばない。クラス内の friend 定義にして、ADL でだけ見える場所にまとめている。
  friend void to_json(json &value, const CommandResult &result) {
    value = json{{"exit_code", result.exit_code}, {"stdout", result.stdout_text},
                 {"stderr", result.stderr_text}};
  }

  friend void from_json(const json &value, CommandResult &result) {
    value.at("exit_code").get_to(result.exit_code);
    value.at("stdout").get_to(result.stdout_text);
    value.at("stderr").get_to(result.stderr_text);
  }
};

// workflow から使わない内部実装。公開 API は dullmify 直下の関数だけである。
namespace detail {

// workflow の例外処理に誤って捕まらない制御合図。問いは Ask、失敗は Failure で伝える。
struct Ask {
  std::string prompt;
  std::string input;
};

struct Failure {
  std::string reason;
};

// report と失敗理由は記録を通らないので、出力時にも置き換える。
inline std::string dump_json(const json &value) {
  return value.dump(-1, ' ', false, json::error_handler_t::replace);
}

// 記録に書く値と読み戻した値を一致させるため、記録する前に不正な UTF-8 を置き換える。
// 置き換えは json.hpp の dump に任せ、その結果を読み戻す。
inline json sanitize_json(const json &value) { return json::parse(dump_json(value)); }

inline std::string trim_one_newline(std::string value) {
  if (!value.empty() && value.back() == '\n') {
    value.pop_back();
    if (!value.empty() && value.back() == '\r') value.pop_back();
  }
  return value;
}

inline std::string read_binary(const fs::path &path) {
  std::ifstream stream(path, std::ios::binary);
  if (!stream) throw std::runtime_error("ファイルを読めません: " + path.string());
  return std::string(std::istreambuf_iterator<char>(stream),
                     std::istreambuf_iterator<char>());
}

class Runtime {
 public:
  // run_dir は絶対パスで受ける。
  explicit Runtime(fs::path run_dir)
      : run_dir_(std::move(run_dir)), records_path_(run_dir_ / "records.jsonl") {
    load_records();
  }

  const std::vector<json> &records() const { return records_; }

  void prepare_answer() {
    const fs::path answer_path = run_dir_ / "answer";
    if (!fs::exists(answer_path)) return;
    for (auto &record : records_) {
      if (record["type"] == "ask" && !record.contains("result")) {
        record["result"] = sanitize_json(trim_one_newline(read_binary(answer_path)));
        save_records();
        break;
      }
    }
    std::error_code ignored;
    fs::remove(answer_path, ignored);
  }

  std::string ask(const std::string &prompt, const std::string &input) {
    reject_nested();
    const json key = sanitize_json(json::array({prompt, input}));
    const Ask signal{key[0], key[1]};
    if (json *record = replay("ask", key)) {
      if (!record->contains("result")) throw signal;
      return record->at("result").get<std::string>();
    }
    if (verifying_) nondeterministic("確認の再実行で新しい問いが現れました");
    records_.push_back(json{{"type", "ask"}, {"key", key}});
    save_records();
    throw signal;
  }

  json recorded(const std::string &type, json key,
                const std::function<json()> &operation, bool reserve) {
    reject_nested();
    key = sanitize_json(key);
    if (json *record = replay(type, key)) {
      // 結果のない記録は、実行前に予約した effect が途中で殺された場合だけにできる。
      if (!record->contains("result")) throw Failure{"前回の副作用が途中で中断されました"};
      return record->at("result");
    }
    if (verifying_) nondeterministic("確認の再実行で新しい " + type + " が現れました");

    json record{{"type", type}, {"key", key}};
    if (reserve) {
      records_.push_back(record);
      save_records();
    }
    struct BlockGuard {
      bool &flag;
      explicit BlockGuard(bool &value) : flag(value) { flag = true; }
      ~BlockGuard() { flag = false; }
    } guard(inside_block_);
    json result;
    try {
      result = sanitize_json(operation());
    } catch (const Ask &) {
      throw;
    } catch (const Failure &) {
      throw;
    } catch (const std::exception &error) {
      throw Failure{type + " の処理で例外が発生しました: " + error.what()};
    } catch (...) {
      throw Failure{type + " の処理で不明な例外が発生しました"};
    }
    if (reserve) {
      records_.back()["result"] = result;
    } else {
      record["result"] = result;
      records_.push_back(record);
    }
    save_records();
    ++cursor_;
    return result;
  }

  void reset_for_verification() {
    cursor_ = 0;
    verifying_ = true;
  }

  void ensure_consumed() {
    if (cursor_ != records_.size()) nondeterministic("workflow が記録を最後まで消費しませんでした");
  }

  const fs::path &run_dir() const { return run_dir_; }

 private:
  fs::path run_dir_;
  fs::path records_path_;
  std::vector<json> records_;
  std::size_t cursor_ = 0;
  bool inside_block_ = false;
  bool verifying_ = false;

  void load_records() {
    if (!fs::exists(records_path_)) return;
    std::ifstream stream(records_path_, std::ios::binary);
    if (!stream) throw Failure{"記録を読めません: " + records_path_.string()};
    std::string line;
    try {
      while (std::getline(stream, line)) records_.push_back(json::parse(line));
    } catch (const std::exception &error) {
      throw Failure{"記録を読めません: " + std::string(error.what())};
    }
    // 読み落とした記録があると副作用を二度行いかねないので、途中で止まった読み取りは失敗にする。
    if (stream.bad()) throw Failure{"記録を読めません: " + records_path_.string()};
  }

  void save_records() {
    const fs::path temporary = run_dir_ / (".records-" + std::to_string(::getpid()) + ".tmp");
    {
      std::ofstream stream(temporary, std::ios::binary | std::ios::trunc);
      if (!stream) throw Failure{"記録の一時ファイルを作れません"};
      for (const auto &record : records_) stream << dump_json(record) << '\n';
      stream.close();
      if (!stream) throw Failure{"記録を書けません"};
    }
    std::error_code error;
    fs::rename(temporary, records_path_, error);
    if (error) {
      fs::remove(temporary);
      throw Failure{"記録を置き換えられません: " + error.message()};
    }
  }

  json *replay(const std::string &type, const json &key) {
    if (cursor_ == records_.size()) return nullptr;
    json &record = records_.at(cursor_);
    if (record["type"] != type || record["key"] != key)
      nondeterministic("記録と補助関数の呼び出しが一致しません");
    ++cursor_;
    return &record;
  }

  void reject_nested() {
    if (inside_block_) throw Failure{"once または effect の中で補助関数を呼べません"};
  }

  [[noreturn]] void nondeterministic(const std::string &detail) {
    throw Failure{"workflow が非決定です: " + detail};
  }
};

inline Runtime *current_runtime = nullptr;

inline Runtime &runtime() {
  if (!current_runtime) throw std::runtime_error("Dullmify のランタイムが開始されていません");
  return *current_runtime;
}

inline CommandResult run_command(const std::vector<std::string> &argv,
                                 const std::string &stdin_text) {
  if (argv.empty()) return {127, "", "コマンドが空です"};
  // 入出力は run ディレクトリのファイルを通すので、大きくてもパイプが詰まらない。
  const fs::path input = runtime().run_dir() / ".command-stdin";
  const fs::path output = runtime().run_dir() / ".command-stdout";
  const fs::path error = runtime().run_dir() / ".command-stderr";
  struct Cleanup {
    const fs::path *paths[3];
    ~Cleanup() {
      std::error_code ignored;
      for (const fs::path *path : paths) fs::remove(*path, ignored);
    }
  } cleanup{{&input, &output, &error}};
  {
    std::ofstream stream(input, std::ios::binary | std::ios::trunc);
    stream.write(stdin_text.data(), static_cast<std::streamsize>(stdin_text.size()));
    stream.close();
    if (!stream) return {127, "", "コマンドの標準入力を準備できません"};
  }

  posix_spawn_file_actions_t actions;
  if (::posix_spawn_file_actions_init(&actions) != 0) return {127, "", "コマンドの起動を準備できません"};
  const bool prepared =
      ::posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, input.c_str(), O_RDONLY, 0) == 0 &&
      ::posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, output.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0600) == 0 &&
      ::posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, error.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0600) == 0;
  std::vector<char *> pointers;
  for (const auto &part : argv) pointers.push_back(const_cast<char *>(part.c_str()));
  pointers.push_back(nullptr);
  // SIGCHLD を無視する親から起動されると子が自動で回収され、終了コードを取れないので既定に戻す。
  std::signal(SIGCHLD, SIG_DFL);
  pid_t child = 0;
  const int spawned =
      prepared ? ::posix_spawnp(&child, pointers[0], &actions, nullptr, pointers.data(), environ) : 0;
  ::posix_spawn_file_actions_destroy(&actions);
  if (!prepared) return {127, "", "コマンドの入出力を準備できません"};
  if (spawned != 0) return {127, "", "コマンドを起動できません: " + std::string(std::strerror(spawned))};

  int status = 0;
  pid_t waited = 0;
  while ((waited = ::waitpid(child, &status, 0)) < 0 && errno == EINTR) {}
  if (waited < 0) return {127, "", "コマンドの終了を待てません: " + std::string(std::strerror(errno))};
  int exit_code = 127;
  if (WIFEXITED(status)) exit_code = WEXITSTATUS(status);
  else if (WIFSIGNALED(status)) exit_code = 128 + WTERMSIG(status);
  return {exit_code, read_binary(output), read_binary(error)};
}

inline void emit(const json &value) { std::cout << dump_json(value) << std::endl; }

// 結果を一つの JSON に集め、片付けと出力は最後に一度だけ行う。
inline int execute(const fs::path &run_argument) {
  std::error_code ignored;
  // 作業ディレクトリを移したあとで片付けるので、先に絶対パスにしておく。
  const fs::path run_dir = fs::absolute(run_argument, ignored);
  json outcome;
  bool keep_run = false;
  try {
    Runtime state(run_dir);
    struct Scope {
      explicit Scope(Runtime &state) { current_runtime = &state; }
      ~Scope() { current_runtime = nullptr; }
    } scope(state);
    state.prepare_answer();
    const std::string arguments = trim_one_newline(read_binary(run_dir / "args"));
    fs::current_path(trim_one_newline(read_binary(run_dir / "cwd")));
    try {
      const std::string first = ::workflow(arguments);
      state.ensure_consumed();
      state.reset_for_verification();
      const std::string second = ::workflow(arguments);
      state.ensure_consumed();
      if (first != second) throw Failure{"workflow が非決定です: 確認の再実行で report が変わりました"};
      outcome = json{{"done", true}, {"report", first}};
    } catch (const Ask &signal) {
      keep_run = true;
      outcome = json{{"run", run_dir.string()}, {"prompt", signal.prompt},
                     {"input", signal.input}, {"write", (run_dir / "answer").string()}};
    }
  } catch (const Failure &failure) {
    outcome = json{{"failed", failure.reason}};
  } catch (const std::exception &error) {
    outcome = json{{"failed", "workflow で例外が発生しました: " + std::string(error.what())}};
  } catch (...) {
    outcome = json{{"failed", "workflow で不明な例外が発生しました"}};
  }
  if (!keep_run) fs::remove_all(run_dir, ignored);
  emit(outcome);
  return 0;
}

}  // detail 名前空間

inline std::string ask(const std::string &prompt, const std::string &input = "") {
  return detail::runtime().ask(prompt, input);
}

[[noreturn]] inline void fail(const std::string &reason) { throw detail::Failure{reason}; }

namespace detail {

// once と effect の共通部分。結果を記録の JSON から呼び出し側の型に戻す。
template <class Function>
auto call_recorded(const std::string &type, const json &key, Function &operation, bool reserve)
    -> std::decay_t<std::invoke_result_t<Function>> {
  using Result = std::decay_t<std::invoke_result_t<Function>>;
  if constexpr (std::is_void_v<Result>) {
    runtime().recorded(type, key, [&]() -> json { operation(); return nullptr; }, reserve);
  } else {
    return runtime().recorded(type, key, [&]() -> json { return json(operation()); }, reserve)
        .template get<Result>();
  }
}

}  // detail 名前空間

template <class Function>
auto once(const json &key, Function &&operation) -> std::decay_t<std::invoke_result_t<Function>> {
  return detail::call_recorded("once", key, operation, false);
}

template <class Function>
auto effect(const json &key, Function &&operation) -> std::decay_t<std::invoke_result_t<Function>> {
  return detail::call_recorded("effect", key, operation, true);
}

inline std::string now() {
  return once(json::array({"now"}), [] {
    const auto point = std::chrono::system_clock::now();
    const auto micros = std::chrono::duration_cast<std::chrono::microseconds>(
        point.time_since_epoch()) % 1000000;
    const std::time_t seconds = std::chrono::system_clock::to_time_t(point);
    std::tm utc{};
    gmtime_r(&seconds, &utc);
    std::ostringstream output;
    output << std::put_time(&utc, "%Y-%m-%dT%H:%M:%S") << '.'
           << std::setw(6) << std::setfill('0') << micros.count() << 'Z';
    return output.str();
  });
}

inline std::string random(std::size_t length) {
  return once(json::array({"random", length}), [length] {
    std::random_device source;
    std::ostringstream output;
    for (std::size_t i = 0; i < length; ++i)
      output << std::hex << std::setw(2) << std::setfill('0') << (source() & 0xFF);
    return output.str();
  });
}

inline std::optional<std::string> env(const std::string &name) {
  const json value = once(json::array({"env", name}), [&]() -> json {
    const char *found = std::getenv(name.c_str());
    return found ? json(found) : json(nullptr);
  });
  if (value.is_null()) return std::nullopt;
  return value.get<std::string>();
}

inline std::optional<std::string> read(const fs::path &path) {
  const json value = once(json::array({"read", path.string()}), [&]() -> json {
    if (!fs::exists(path)) return json(nullptr);
    return json(detail::read_binary(path));
  });
  if (value.is_null()) return std::nullopt;
  return value.get<std::string>();
}

inline void write(const fs::path &path, const std::string &content) {
  effect(json::array({"write", path.string(), content}), [&] {
    if (!path.parent_path().empty()) fs::create_directories(path.parent_path());
    std::ofstream stream(path, std::ios::binary | std::ios::trunc);
    if (!stream) throw std::runtime_error("ファイルを開けません: " + path.string());
    stream.write(content.data(), static_cast<std::streamsize>(content.size()));
    stream.close();
    if (!stream) throw std::runtime_error("ファイルを書けません: " + path.string());
  });
}

inline CommandResult command(const std::vector<std::string> &argv,
                             const std::string &stdin_text = "") {
  return effect(json::array({"command", argv, stdin_text}),
                [&] { return detail::run_command(argv, stdin_text); });
}

}  // dullmify 名前空間

#ifndef DULLMIFY_NO_MAIN
int main(int, char **argv) {
  return dullmify::detail::execute(argv[1]);
}
#endif

#endif
