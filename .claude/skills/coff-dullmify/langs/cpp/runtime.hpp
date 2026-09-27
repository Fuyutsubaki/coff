// dullmify C++ runtime (C++17, POSIX). Included by workflow.cpp, which defines
//   std::string workflow();
//
// Usage (normally through `run`, which builds the binary and passes the hash):
//   <binary> <workflow hash> start             creates a run directory, prints where to write the arguments
//   <binary> <workflow hash> continue <run>    takes in what was written (args, or the pending answer) and re-runs
//
// The workflow is re-run from the top on every `continue`. Recorded questions
// and side effects return their recorded results; the first unanswered
// question is recorded, printed as JSON, and the process exits. Arguments and
// answers arrive as files in the run directory, written by the caller.
//
// Run directory (under ${TMPDIR:-/tmp}):
//   .dullmify-run   marker
//   cwd             working directory at start
//   workflow.hash   hash of workflow.cpp + runtime.hpp at start (from `run`)
//   args            the skill's arguments, verbatim (written by the caller)
//   answer.<n>      the answer to ask <n> (written by the caller, consumed by continue)
//   records         one record per helper call
//
// Record format (no JSON library needed):
//   <kind> <ask_no> <key_len> <result_len>\n<key>\n<result>\n
//   result_len is -1 for an unanswered ask, and then the result line is absent.
#ifndef DULLMIFY_RUNTIME_HPP
#define DULLMIFY_RUNTIME_HPP

#include <cerrno>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <optional>
#include <string>
#include <vector>

#include <dirent.h>
#include <fcntl.h>
#include <poll.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

std::string workflow(); // defined by workflow.cpp

namespace dullmify {

struct CommandResult {
  int status;
  std::string out;
  std::string err;
};

std::string args();
std::string ask(const std::string& prompt, const std::string& input = "");
CommandResult run_command(const std::vector<std::string>& argv, const std::string& stdin_data = "");
std::optional<std::string> read_file(const std::string& path);
void write_file(const std::string& path, const std::string& content);
[[noreturn]] void fail(const std::string& reason);

namespace detail {

// Thrown to leave the workflow. Neither derives from std::exception, so a
// workflow's `catch (const std::exception&)` cannot swallow them.
struct Suspend {
  int ask_no;
  std::string prompt;
  std::string input;
};
struct Failure {
  std::string reason;
};

struct Record {
  std::string kind;
  int ask_no = 0;
  std::string key;
  bool pending = false;
  std::string result;
};

struct State {
  std::string run_dir;
  std::string cwd;
  std::string args;
  std::vector<Record> records;
  size_t cursor = 0;
  bool suspended = false;
  Suspend pending; // the question being asked, once suspended
};

inline State& state() {
  static State s;
  return s;
}

inline const char* marker_name() { return ".dullmify-run"; }

// --- small file utilities --------------------------------------------------

inline bool read_whole(const std::string& path, std::string& out) {
  FILE* f = std::fopen(path.c_str(), "rb");
  if (!f) return false;
  out.clear();
  char buf[65536];
  size_t n;
  while ((n = std::fread(buf, 1, sizeof buf, f)) > 0) out.append(buf, n);
  std::fclose(f);
  return true;
}

inline void write_whole(const std::string& path, const std::string& data, bool append = false) {
  FILE* f = std::fopen(path.c_str(), append ? "ab" : "wb");
  if (!f) throw Failure{"cannot write " + path + ": " + std::strerror(errno)};
  if (!data.empty() && std::fwrite(data.data(), 1, data.size(), f) != data.size()) {
    std::fclose(f);
    throw Failure{"short write to " + path};
  }
  std::fclose(f);
}

inline void mkdir_p(const std::string& dir) {
  if (dir.empty() || dir == "." || dir == "/") return;
  struct stat st;
  if (::stat(dir.c_str(), &st) == 0) return;
  size_t slash = dir.find_last_of('/');
  if (slash != std::string::npos && slash > 0) mkdir_p(dir.substr(0, slash));
  if (::mkdir(dir.c_str(), 0777) != 0 && errno != EEXIST)
    throw Failure{"cannot create directory " + dir + ": " + std::strerror(errno)};
}

inline std::string join(const std::string& dir, const char* name) { return dir + "/" + name; }

inline void remove_run() {
  const std::string& dir = state().run_dir;
  if (dir.empty()) return;
  if (DIR* d = ::opendir(dir.c_str())) {
    while (dirent* e = ::readdir(d)) {
      std::string name = e->d_name;
      if (name == "." || name == "..") continue;
      ::unlink(join(dir, e->d_name).c_str());
    }
    ::closedir(d);
  }
  ::rmdir(dir.c_str());
}

// --- hashing (FNV-1a 64) ---------------------------------------------------

inline std::string fnv1a(const std::string& data) {
  uint64_t h = 1469598103934665603ULL;
  for (unsigned char c : data) {
    h ^= c;
    h *= 1099511628211ULL;
  }
  char buf[17];
  std::snprintf(buf, sizeof buf, "%016llx", static_cast<unsigned long long>(h));
  return buf;
}

inline std::string digest(const std::vector<std::string>& parts) {
  std::string joined;
  for (size_t i = 0; i < parts.size(); ++i) {
    if (i) joined.push_back('\0');
    joined += parts[i];
  }
  return fnv1a(joined);
}

// --- records ---------------------------------------------------------------

inline std::string format_record(const Record& r) {
  std::string s = r.kind + " " + std::to_string(r.ask_no) + " " + std::to_string(r.key.size()) + " " +
                  (r.pending ? std::string("-1") : std::to_string(r.result.size())) + "\n" + r.key + "\n";
  if (!r.pending) s += r.result + "\n";
  return s;
}

inline std::string records_path() { return join(state().run_dir, "records"); }

inline void append_record(const Record& r) { write_whole(records_path(), format_record(r), true); }

inline void rewrite_records() {
  std::string all;
  for (const Record& r : state().records) all += format_record(r);
  write_whole(records_path(), all);
}

inline std::vector<Record> load_records() {
  std::string data;
  if (!read_whole(records_path(), data)) throw Failure{"cannot read records"};
  std::vector<Record> records;
  size_t pos = 0;
  while (pos < data.size()) {
    size_t nl = data.find('\n', pos);
    if (nl == std::string::npos) throw Failure{"corrupt records"};
    std::string header = data.substr(pos, nl - pos);
    pos = nl + 1;
    char kind[32];
    int ask_no = 0;
    long key_len = 0, result_len = 0;
    if (std::sscanf(header.c_str(), "%31s %d %ld %ld", kind, &ask_no, &key_len, &result_len) != 4)
      throw Failure{"corrupt records"};
    Record r;
    r.kind = kind;
    r.ask_no = ask_no;
    r.key = data.substr(pos, static_cast<size_t>(key_len));
    pos += static_cast<size_t>(key_len) + 1;
    if (result_len < 0) {
      r.pending = true;
    } else {
      r.result = data.substr(pos, static_cast<size_t>(result_len));
      pos += static_cast<size_t>(result_len) + 1;
    }
    records.push_back(r);
  }
  return records;
}

// Returns the recorded result for this call, or nullptr when the call is new.
inline const Record* replay(const std::string& kind, const std::string& key) {
  State& s = state();
  if (s.cursor >= s.records.size()) return nullptr;
  const Record& r = s.records[s.cursor];
  if (r.kind != kind || r.key != key)
    throw Failure{"nondeterministic replay: record " + std::to_string(s.cursor + 1) + " is " + r.kind +
                  ", but the workflow requested a different " + kind};
  if (r.pending) throw Failure{"nondeterministic replay: record " + std::to_string(s.cursor + 1) + " has no answer"};
  ++s.cursor;
  return &r;
}

inline void record(const std::string& kind, const std::string& key, const std::string& result) {
  Record r;
  r.kind = kind;
  r.key = key;
  r.result = result;
  state().records.push_back(r);
  ++state().cursor;
  append_record(r);
}

// --- JSON output -----------------------------------------------------------

inline std::string json_escape(const std::string& s) {
  std::string out = "\"";
  for (unsigned char c : s) {
    switch (c) {
      case '"': out += "\\\""; break;
      case '\\': out += "\\\\"; break;
      case '\n': out += "\\n"; break;
      case '\r': out += "\\r"; break;
      case '\t': out += "\\t"; break;
      default:
        if (c < 0x20) {
          char buf[8];
          std::snprintf(buf, sizeof buf, "\\u%04x", c);
          out += buf;
        } else {
          out.push_back(static_cast<char>(c));
        }
    }
  }
  return out + "\"";
}

inline void emit(const std::string& json) {
  std::fputs(json.c_str(), stdout);
  std::fputc('\n', stdout);
  std::fflush(stdout);
}

inline void emit_failed(const std::string& reason) {
  emit("{\"failed\":" + json_escape(reason) + "}");
  remove_run();
}

inline void emit_ask(const Suspend& q) {
  const std::string& run = state().run_dir;
  emit("{\"run\":" + json_escape(run) + ",\"ask\":" + std::to_string(q.ask_no) +
       ",\"prompt\":" + json_escape(q.prompt) + ",\"input\":" + json_escape(q.input) +
       ",\"write\":" + json_escape(run + "/answer." + std::to_string(q.ask_no)) + "}");
}

// --- command execution -----------------------------------------------------

inline CommandResult exec_command(const std::vector<std::string>& argv, const std::string& stdin_data) {
  CommandResult res{127, "", ""};
  // stdin goes through a temp file so writing it cannot deadlock against the
  // child's output.
  std::string tmpdir = std::getenv("TMPDIR") ? std::getenv("TMPDIR") : "/tmp";
  std::string stdin_path = tmpdir + "/dullmify-stdin.XXXXXX";
  std::vector<char> tmpl(stdin_path.begin(), stdin_path.end());
  tmpl.push_back('\0');
  int in_fd = ::mkstemp(tmpl.data());
  if (in_fd < 0) {
    res.err = std::string("mkstemp: ") + std::strerror(errno);
    return res;
  }
  stdin_path = tmpl.data();
  if (!stdin_data.empty()) {
    size_t off = 0;
    while (off < stdin_data.size()) {
      ssize_t w = ::write(in_fd, stdin_data.data() + off, stdin_data.size() - off);
      if (w <= 0) break;
      off += static_cast<size_t>(w);
    }
  }
  ::lseek(in_fd, 0, SEEK_SET);

  int out_pipe[2], err_pipe[2];
  if (::pipe(out_pipe) != 0 || ::pipe(err_pipe) != 0) {
    res.err = std::string("pipe: ") + std::strerror(errno);
    ::close(in_fd);
    ::unlink(stdin_path.c_str());
    return res;
  }
  pid_t pid = ::fork();
  if (pid < 0) {
    res.err = std::string("fork: ") + std::strerror(errno);
    ::close(in_fd);
    ::unlink(stdin_path.c_str());
    return res;
  }
  if (pid == 0) {
    ::dup2(in_fd, 0);
    ::dup2(out_pipe[1], 1);
    ::dup2(err_pipe[1], 2);
    ::close(in_fd);
    ::close(out_pipe[0]);
    ::close(out_pipe[1]);
    ::close(err_pipe[0]);
    ::close(err_pipe[1]);
    std::vector<char*> cargv;
    for (const std::string& a : argv) cargv.push_back(const_cast<char*>(a.c_str()));
    cargv.push_back(nullptr);
    ::execvp(cargv[0], cargv.data());
    std::fprintf(stderr, "%s: %s\n", cargv[0], std::strerror(errno));
    ::_exit(127);
  }
  ::close(in_fd);
  ::close(out_pipe[1]);
  ::close(err_pipe[1]);
  pollfd fds[2] = {{out_pipe[0], POLLIN, 0}, {err_pipe[0], POLLIN, 0}};
  std::string* sinks[2] = {&res.out, &res.err};
  int open_fds = 2;
  char buf[65536];
  while (open_fds > 0) {
    if (::poll(fds, 2, -1) < 0) {
      if (errno == EINTR) continue;
      break;
    }
    for (int i = 0; i < 2; ++i) {
      if (fds[i].fd < 0 || !(fds[i].revents & (POLLIN | POLLHUP | POLLERR))) continue;
      ssize_t n = ::read(fds[i].fd, buf, sizeof buf);
      if (n > 0) {
        sinks[i]->append(buf, static_cast<size_t>(n));
      } else {
        ::close(fds[i].fd);
        fds[i].fd = -1;
        --open_fds;
      }
    }
  }
  int status = 0;
  while (::waitpid(pid, &status, 0) < 0 && errno == EINTR) {
  }
  ::unlink(stdin_path.c_str());
  if (WIFEXITED(status)) res.status = WEXITSTATUS(status);
  else if (WIFSIGNALED(status)) res.status = 128 + WTERMSIG(status);
  return res;
}

inline std::string encode_command(const CommandResult& r) {
  return std::to_string(r.status) + "\n" + std::to_string(r.out.size()) + "\n" + r.out + r.err;
}

inline CommandResult decode_command(const std::string& data) {
  CommandResult r{0, "", ""};
  size_t nl1 = data.find('\n');
  size_t nl2 = data.find('\n', nl1 + 1);
  r.status = std::atoi(data.substr(0, nl1).c_str());
  size_t out_len = static_cast<size_t>(std::atol(data.substr(nl1 + 1, nl2 - nl1 - 1).c_str()));
  r.out = data.substr(nl2 + 1, out_len);
  r.err = data.substr(nl2 + 1 + out_len);
  return r;
}

// --- entry point -----------------------------------------------------------

// A file written by the caller, minus one trailing newline. False if absent.
inline bool read_input(const std::string& path, std::string& out) {
  if (!read_whole(path, out)) return false;
  if (!out.empty() && out.back() == '\n') out.pop_back();
  return true;
}

inline std::string read_line_file(const char* name) {
  std::string s;
  read_whole(join(state().run_dir, name), s);
  if (!s.empty() && s.back() == '\n') s.pop_back();
  return s;
}

inline int usage() {
  std::fputs("usage: run start | run continue <run>\n", stderr);
  return 2;
}

inline int execute() {
  State& s = state();
  try {
    if (::chdir(s.cwd.c_str()) != 0) throw Failure{"cannot enter " + s.cwd + ": " + std::strerror(errno)};
    std::string report = workflow();
    if (s.cursor < s.records.size())
      throw Failure{"nondeterministic replay: the workflow finished after reusing " + std::to_string(s.cursor) +
                    " of " + std::to_string(s.records.size()) + " records"};
    emit("{\"done\":true,\"report\":" + json_escape(report) + "}");
    remove_run();
  } catch (const Suspend& q) {
    emit_ask(q);
  } catch (const Failure& f) {
    emit_failed(f.reason);
  } catch (const std::exception& e) {
    emit_failed(std::string("exception: ") + e.what());
  } catch (...) {
    emit_failed("unknown exception");
  }
  return 0;
}

inline int main(int argc, char** argv) {
  if (argc < 3) return usage();
  std::string hash = argv[1];
  std::string cmd = argv[2];
  State& s = state();
  if (cmd == "start") {
    if (argc != 3) return usage();
    std::string tmpdir = std::getenv("TMPDIR") ? std::getenv("TMPDIR") : "/tmp";
    std::string tmpl_s = tmpdir + "/dullmify-run.XXXXXX";
    std::vector<char> tmpl(tmpl_s.begin(), tmpl_s.end());
    tmpl.push_back('\0');
    if (!::mkdtemp(tmpl.data())) {
      std::fprintf(stderr, "cannot create run directory: %s\n", std::strerror(errno));
      return 2;
    }
    s.run_dir = tmpl.data();
    char cwd[4096];
    if (!::getcwd(cwd, sizeof cwd)) {
      std::fprintf(stderr, "getcwd: %s\n", std::strerror(errno));
      return 2;
    }
    try {
      write_whole(join(s.run_dir, marker_name()), "");
      write_whole(join(s.run_dir, "cwd"), std::string(cwd) + "\n");
      write_whole(join(s.run_dir, "workflow.hash"), hash + "\n");
      write_whole(records_path(), "");
    } catch (const Failure& f) {
      std::fprintf(stderr, "%s\n", f.reason.c_str());
      return 2;
    }
    emit("{\"run\":" + json_escape(s.run_dir) + ",\"write\":" + json_escape(join(s.run_dir, "args")) + "}");
    return 0;
  }
  if (cmd != "continue" || argc != 4) return usage();
  s.run_dir = argv[3];
  struct stat st;
  if (::stat(join(s.run_dir, marker_name()).c_str(), &st) != 0 || !S_ISREG(st.st_mode)) {
    std::fprintf(stderr, "not a dullmify run: %s\n", s.run_dir.c_str());
    return 2;
  }
  if (read_line_file("workflow.hash") != hash) {
    emit_failed("workflow changed since the run started");
    return 0;
  }
  try {
    s.records = load_records();
  } catch (const Failure& f) {
    emit_failed(f.reason);
    return 0;
  } catch (const std::exception&) {
    emit_failed("corrupt records");
    return 0;
  }
  if (!read_input(join(s.run_dir, "args"), s.args)) {
    std::fprintf(stderr, "write the arguments to %s first (an empty file if there are none), then continue\n",
                 join(s.run_dir, "args").c_str());
    return 2;
  }
  if (!s.records.empty() && s.records.back().kind == "ask" && s.records.back().pending) {
    Record& pending = s.records.back();
    std::string answer_path = s.run_dir + "/answer." + std::to_string(pending.ask_no);
    std::string answer;
    if (!read_input(answer_path, answer)) {
      std::fprintf(stderr, "write the answer to ask %d to %s first, then continue\n", pending.ask_no,
                   answer_path.c_str());
      return 2;
    }
    pending.pending = false;
    pending.result = answer;
    try {
      rewrite_records();
    } catch (const Failure& f) {
      std::fprintf(stderr, "%s\n", f.reason.c_str());
      return 2;
    }
    ::unlink(answer_path.c_str());
  }
  s.cwd = read_line_file("cwd");
  return execute();
}

} // namespace detail

// --- helpers for the workflow ----------------------------------------------

inline std::string args() { return detail::state().args; }

inline std::string ask(const std::string& prompt, const std::string& input) {
  detail::State& s = detail::state();
  std::string key = detail::digest({"ask", prompt, input});
  if (s.suspended) return "";
  if (const detail::Record* r = detail::replay("ask", key)) return r->result;
  int ask_no = 1;
  for (const detail::Record& r : s.records)
    if (r.kind == "ask") ++ask_no;
  detail::Record r;
  r.kind = "ask";
  r.ask_no = ask_no;
  r.key = key;
  r.pending = true;
  s.records.push_back(r);
  detail::append_record(r);
  s.suspended = true;
  s.pending = detail::Suspend{ask_no, prompt, input};
  throw s.pending;
}

inline CommandResult run_command(const std::vector<std::string>& argv, const std::string& stdin_data) {
  detail::State& s = detail::state();
  std::string joined;
  for (size_t i = 0; i < argv.size(); ++i) {
    if (i) joined.push_back('\0');
    joined += argv[i];
  }
  std::string key = detail::digest({"cmd", joined, stdin_data});
  if (s.suspended) return CommandResult{0, "", ""};
  if (const detail::Record* r = detail::replay("cmd", key)) return detail::decode_command(r->result);
  CommandResult res = detail::exec_command(argv, stdin_data);
  detail::record("cmd", key, detail::encode_command(res));
  return res;
}

inline std::optional<std::string> read_file(const std::string& path) {
  detail::State& s = detail::state();
  std::string key = detail::digest({"read", path});
  if (s.suspended) return std::nullopt;
  if (const detail::Record* r = detail::replay("read", key)) {
    if (r->result.empty() || r->result[0] != '1') return std::nullopt;
    return r->result.substr(1);
  }
  std::string content;
  struct stat st;
  bool exists = ::stat(path.c_str(), &st) == 0 && S_ISREG(st.st_mode) && detail::read_whole(path, content);
  detail::record("read", key, exists ? "1" + content : std::string("0"));
  if (!exists) return std::nullopt;
  return content;
}

inline void write_file(const std::string& path, const std::string& content) {
  detail::State& s = detail::state();
  std::string key = detail::digest({"write", path, detail::fnv1a(content)});
  if (s.suspended) return;
  if (detail::replay("write", key)) return;
  size_t slash = path.find_last_of('/');
  if (slash != std::string::npos) detail::mkdir_p(path.substr(0, slash));
  detail::write_whole(path, content);
  detail::record("write", key, "");
}

[[noreturn]] inline void fail(const std::string& reason) {
  detail::State& s = detail::state();
  if (s.suspended) {
    // Called from a destructor while the question propagates: throwing here
    // would terminate the process. The question is already recorded, so
    // print it and leave without running further destructors.
    detail::emit_ask(s.pending);
    std::_Exit(0);
  }
  throw detail::Failure{reason};
}

} // namespace dullmify

int main(int argc, char** argv) { return dullmify::detail::main(argc, argv); }

#endif
