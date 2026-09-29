#ifndef COFF_DULLMIFY_RUNTIME_HPP
#define COFF_DULLMIFY_RUNTIME_HPP

#include "json.hpp"

#include <array>
#include <cerrno>
#include <chrono>
#include <cstdio>
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

#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

std::string workflow();

namespace dullmify {

using json = nlohmann::json;
namespace fs = std::filesystem;

// workflow の例外処理に誤って捕まらない制御合図。
struct Control {
  enum class Kind { ask, failed } kind;
  std::string prompt;
  std::string input;
  std::string reason;
};

struct Failure {
  std::string reason;
};

struct CommandResult {
  int exit_code;
  std::string stdout_text;
  std::string stderr_text;
};

inline void to_json(json &value, const CommandResult &result) {
  value = json{{"exit_code", result.exit_code}, {"stdout", result.stdout_text},
               {"stderr", result.stderr_text}};
}

inline void from_json(const json &value, CommandResult &result) {
  value.at("exit_code").get_to(result.exit_code);
  value.at("stdout").get_to(result.stdout_text);
  value.at("stderr").get_to(result.stderr_text);
}

inline std::string sanitize_utf8(const std::string &source) {
  const std::string replacement = "\xEF\xBF\xBD";
  std::string output;
  for (std::size_t i = 0; i < source.size();) {
    const unsigned char first = static_cast<unsigned char>(source[i]);
    if (first < 0x80) {
      output.push_back(source[i++]);
      continue;
    }
    std::size_t length = 0;
    unsigned int codepoint = 0;
    unsigned int minimum = 0;
    if (first >= 0xC2 && first <= 0xDF) {
      length = 2; codepoint = first & 0x1F; minimum = 0x80;
    } else if (first >= 0xE0 && first <= 0xEF) {
      length = 3; codepoint = first & 0x0F; minimum = 0x800;
    } else if (first >= 0xF0 && first <= 0xF4) {
      length = 4; codepoint = first & 0x07; minimum = 0x10000;
    } else {
      output += replacement;
      ++i;
      continue;
    }
    bool valid = i + length <= source.size();
    for (std::size_t j = 1; valid && j < length; ++j) {
      const unsigned char next = static_cast<unsigned char>(source[i + j]);
      valid = (next & 0xC0) == 0x80;
      if (valid) codepoint = (codepoint << 6) | (next & 0x3F);
    }
    valid = valid && codepoint >= minimum && codepoint <= 0x10FFFF &&
            !(codepoint >= 0xD800 && codepoint <= 0xDFFF);
    if (!valid) {
      output += replacement;
      ++i;
      continue;
    }
    output.append(source, i, length);
    i += length;
  }
  return output;
}

inline json sanitize_json(const json &value) {
  if (value.is_string()) return sanitize_utf8(value.get<std::string>());
  if (value.is_array()) {
    json output = json::array();
    for (const auto &item : value) output.push_back(sanitize_json(item));
    return output;
  }
  if (value.is_object()) {
    json output = json::object();
    for (auto it = value.begin(); it != value.end(); ++it)
      output[sanitize_utf8(it.key())] = sanitize_json(it.value());
    return output;
  }
  return value;
}

inline std::string dump_json(const json &value) {
  return sanitize_json(value).dump(-1, ' ', false, json::error_handler_t::replace);
}

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
  explicit Runtime(fs::path run_dir)
      : run_dir_(fs::absolute(std::move(run_dir))), records_path_(run_dir_ / "records.jsonl") {
    load_records();
  }

  const std::vector<json> &records() const { return records_; }

  void prepare_answer() {
    const fs::path answer_path = run_dir_ / "answer";
    if (!fs::exists(answer_path)) return;
    for (auto &record : records_) {
      if (record.value("type", "") == "ask" && !record.contains("result")) {
        record["result"] = sanitize_utf8(trim_one_newline(read_binary(answer_path)));
        save_records();
        break;
      }
    }
    std::error_code ignored;
    fs::remove(answer_path, ignored);
  }

  std::string arguments() {
    reject_nested();
    return sanitize_utf8(trim_one_newline(read_binary(run_dir_ / "args")));
  }

  std::string ask(std::string prompt, std::string input) {
    reject_nested();
    prompt = sanitize_utf8(prompt);
    input = sanitize_utf8(input);
    const json key = json::array({prompt, input});
    if (json *record = replay("ask", key)) {
      if (!record->contains("result")) throw Control{Control::Kind::ask, prompt, input, ""};
      return record->at("result").get<std::string>();
    }
    if (verifying_) nondeterministic("確認の再実行で新しい問いが現れました");
    records_.push_back(json{{"type", "ask"}, {"key", key}});
    save_records();
    throw Control{Control::Kind::ask, prompt, input, ""};
  }

  json recorded(const std::string &type, json key,
                const std::function<json()> &operation, bool reserve) {
    reject_nested();
    key = sanitize_json(key);
    if (json *record = replay(type, key)) {
      if (!record->contains("result")) {
        throw Failure{type == "effect" ? "前回の副作用が途中で中断されました"
                                         : "未完了の記録があります"};
      }
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
    } catch (const Control &) {
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

  void save_records() {
    const fs::path temporary = run_dir_ / (".records-" + std::to_string(::getpid()) + ".tmp");
    {
      std::ofstream stream(temporary, std::ios::binary | std::ios::trunc);
      if (!stream) throw Failure{"記録の一時ファイルを作れません"};
      for (const auto &record : records_) stream << dump_json(record) << '\n';
      if (!stream) throw Failure{"記録を書けません"};
    }
    std::error_code error;
    fs::rename(temporary, records_path_, error);
    if (error) {
      fs::remove(temporary);
      throw Failure{"記録を置き換えられません: " + error.message()};
    }
  }

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
    std::string line;
    try {
      while (std::getline(stream, line)) records_.push_back(json::parse(line));
    } catch (const std::exception &error) {
      throw Failure{"記録を読めません: " + std::string(error.what())};
    }
    if (!stream.eof()) throw Failure{"記録を最後まで読めません"};
  }

  json *replay(const std::string &type, const json &key) {
    if (cursor_ == records_.size()) return nullptr;
    json &record = records_.at(cursor_);
    if (record.value("type", "") != type || !record.contains("key") || record["key"] != key)
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

inline std::string arguments() { return runtime().arguments(); }
inline std::string ask(const std::string &prompt, const std::string &input = "") {
  return runtime().ask(prompt, input);
}

[[noreturn]] inline void fail(const std::string &reason) {
  throw Control{Control::Kind::failed, "", "", sanitize_utf8(reason)};
}

template <class Function>
auto once(const json &key, Function &&operation)
    -> std::decay_t<std::invoke_result_t<Function>> {
  using Result = std::decay_t<std::invoke_result_t<Function>>;
  if constexpr (std::is_void_v<Result>) {
    runtime().recorded("once", key, [&]() -> json { operation(); return nullptr; }, false);
  } else {
    json value = runtime().recorded("once", key, [&]() -> json { return json(operation()); }, false);
    return value.template get<Result>();
  }
}

template <class Function>
auto effect(const json &key, Function &&operation)
    -> std::decay_t<std::invoke_result_t<Function>> {
  using Result = std::decay_t<std::invoke_result_t<Function>>;
  if constexpr (std::is_void_v<Result>) {
    runtime().recorded("effect", key, [&]() -> json { operation(); return nullptr; }, true);
  } else {
    json value = runtime().recorded("effect", key, [&]() -> json { return json(operation()); }, true);
    return value.template get<Result>();
  }
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
  json value = runtime().recorded("once", json::array({"env", name}), [name] {
    const char *found = std::getenv(name.c_str());
    return found ? json(sanitize_utf8(found)) : json(nullptr);
  }, false);
  if (value.is_null()) return std::nullopt;
  return value.get<std::string>();
}

inline std::optional<std::string> read(const fs::path &path) {
  const std::string name = path.string();
  json value = runtime().recorded("once", json::array({"read", name}), [path] {
    if (!fs::exists(path)) return json(nullptr);
    return json(sanitize_utf8(read_binary(path)));
  }, false);
  if (value.is_null()) return std::nullopt;
  return value.get<std::string>();
}

inline void write(const fs::path &path, const std::string &content) {
  const std::string name = path.string();
  const std::string clean = sanitize_utf8(content);
  effect(json::array({"write", name, clean}), [path, clean] {
    if (!path.parent_path().empty()) fs::create_directories(path.parent_path());
    std::ofstream stream(path, std::ios::binary | std::ios::trunc);
    if (!stream) throw std::runtime_error("ファイルを開けません: " + path.string());
    stream.write(clean.data(), static_cast<std::streamsize>(clean.size()));
    if (!stream) throw std::runtime_error("ファイルを書けません: " + path.string());
  });
}

inline int temporary_fd(const fs::path &run_dir, const std::string &label) {
  std::string pattern = (run_dir / ("." + label + ".XXXXXX")).string();
  std::vector<char> buffer(pattern.begin(), pattern.end());
  buffer.push_back('\0');
  const int fd = ::mkstemp(buffer.data());
  if (fd >= 0) ::unlink(buffer.data());
  return fd;
}

inline bool write_all(int fd, const std::string &content) {
  std::size_t offset = 0;
  while (offset < content.size()) {
    const ssize_t count = ::write(fd, content.data() + offset, content.size() - offset);
    if (count < 0 && errno == EINTR) continue;
    if (count <= 0) return false;
    offset += static_cast<std::size_t>(count);
  }
  return true;
}

inline std::string read_fd(int fd) {
  ::lseek(fd, 0, SEEK_SET);
  std::string output;
  std::array<char, 4096> buffer{};
  for (;;) {
    const ssize_t count = ::read(fd, buffer.data(), buffer.size());
    if (count < 0 && errno == EINTR) continue;
    if (count <= 0) break;
    output.append(buffer.data(), static_cast<std::size_t>(count));
  }
  return sanitize_utf8(output);
}

inline CommandResult run_command(const std::vector<std::string> &argv,
                                 const std::string &stdin_text) {
  if (argv.empty()) return {127, "", "コマンドが空です"};
  const int input_fd = temporary_fd(runtime().run_dir(), "stdin");
  const int output_fd = temporary_fd(runtime().run_dir(), "stdout");
  const int error_fd = temporary_fd(runtime().run_dir(), "stderr");
  if (input_fd < 0 || output_fd < 0 || error_fd < 0) {
    if (input_fd >= 0) ::close(input_fd);
    if (output_fd >= 0) ::close(output_fd);
    if (error_fd >= 0) ::close(error_fd);
    return {127, "", "コマンド用の一時ファイルを作れません"};
  }
  if (!write_all(input_fd, stdin_text) || ::lseek(input_fd, 0, SEEK_SET) < 0) {
    ::close(input_fd); ::close(output_fd); ::close(error_fd);
    return {127, "", "コマンドの標準入力を準備できません"};
  }
  const pid_t child = ::fork();
  if (child < 0) {
    ::close(input_fd); ::close(output_fd); ::close(error_fd);
    return {127, "", "コマンドを起動できません: " + std::string(std::strerror(errno))};
  }
  if (child == 0) {
    ::dup2(input_fd, STDIN_FILENO);
    ::dup2(output_fd, STDOUT_FILENO);
    ::dup2(error_fd, STDERR_FILENO);
    ::close(input_fd); ::close(output_fd); ::close(error_fd);
    std::vector<char *> arguments;
    for (const auto &part : argv) arguments.push_back(const_cast<char *>(part.c_str()));
    arguments.push_back(nullptr);
    ::execvp(arguments[0], arguments.data());
    const std::string message = "コマンドを起動できません: " + std::string(std::strerror(errno)) + "\n";
    write_all(STDERR_FILENO, message);
    ::_exit(127);
  }
  ::close(input_fd);
  int status = 0;
  while (::waitpid(child, &status, 0) < 0 && errno == EINTR) {}
  const std::string stdout_text = read_fd(output_fd);
  const std::string stderr_text = read_fd(error_fd);
  ::close(output_fd); ::close(error_fd);
  int exit_code = 127;
  if (WIFEXITED(status)) exit_code = WEXITSTATUS(status);
  else if (WIFSIGNALED(status)) exit_code = 128 + WTERMSIG(status);
  return {exit_code, stdout_text, stderr_text};
}

inline CommandResult command(const std::vector<std::string> &argv,
                             const std::string &stdin_text = "") {
  return effect(json::array({"command", argv, sanitize_utf8(stdin_text)}),
                [&] { return run_command(argv, sanitize_utf8(stdin_text)); });
}

inline void emit(const json &value) { std::cout << dump_json(value) << std::endl; }

inline int execute(const fs::path &run_dir) {
  try {
    Runtime state(run_dir);
    state.prepare_answer();
    fs::current_path(trim_one_newline(read_binary(state.run_dir() / "cwd")));
    current_runtime = &state;
    std::string first;
    try {
      first = sanitize_utf8(::workflow());
      state.ensure_consumed();
      state.reset_for_verification();
      const std::string second = sanitize_utf8(::workflow());
      state.ensure_consumed();
      if (first != second) throw Failure{"workflow が非決定です: 確認の再実行で report が変わりました"};
    } catch (const Control &signal) {
      current_runtime = nullptr;
      if (signal.kind == Control::Kind::ask) {
        emit(json{{"run", state.run_dir().string()}, {"prompt", signal.prompt},
                  {"input", signal.input}, {"write", (state.run_dir() / "answer").string()}});
        return 0;
      }
      fs::remove_all(state.run_dir());
      emit(json{{"failed", signal.reason}});
      return 0;
    }
    current_runtime = nullptr;
    fs::remove_all(state.run_dir());
    emit(json{{"done", true}, {"report", first}});
  } catch (const Failure &failure) {
    current_runtime = nullptr;
    std::error_code ignored;
    fs::remove_all(run_dir, ignored);
    emit(json{{"failed", sanitize_utf8(failure.reason)}});
  } catch (const std::exception &error) {
    current_runtime = nullptr;
    std::error_code ignored;
    fs::remove_all(run_dir, ignored);
    emit(json{{"failed", "workflow で例外が発生しました: " + sanitize_utf8(error.what())}});
  } catch (...) {
    current_runtime = nullptr;
    std::error_code ignored;
    fs::remove_all(run_dir, ignored);
    emit(json{{"failed", "workflow で不明な例外が発生しました"}});
  }
  return 0;
}

}  // dullmify 名前空間

#ifndef DULLMIFY_NO_MAIN
int main(int argc, char **argv) {
  if (argc != 2) {
    std::cerr << "run ディレクトリを一つ指定してください" << std::endl;
    return 2;
  }
  return dullmify::execute(argv[1]);
}
#endif

#endif
