# Writing a workflow in C++

File name: `workflow.cpp`.

`workflow.cpp` includes `runtime.hpp` and defines `std::string workflow()`, which returns the
report. The launcher builds it with `${CXX:-c++} -std=c++17` on first use. The program is re-run
from the top after every answer, so control flow must depend only on `args()`, answers, and
helper results. Every interaction with the outside world goes through the helpers below;
anything else is a bug and `check` rejects it.

## Helpers (namespace `dullmify`)

- `std::string args()`. The arguments given to the skill, verbatim. Split them yourself.
- `std::string ask(const std::string& prompt, const std::string& input = "")`. Asks the LLM.
  `prompt` says what to answer and how; `input` is the data to look at.
- `CommandResult run_command(const std::vector<std::string>& argv, const std::string& stdin = "")`
  with members `status`, `out`, `err`. No shell is involved. A non-zero status does not throw.
- `std::optional<std::string> read_file(const std::string& path)`. Empty when the file does
  not exist.
- `void write_file(const std::string& path, const std::string& content)`. Creates parent
  directories.
- `[[noreturn]] void fail(const std::string& reason)`. Stops the run as failed.

Relative paths are resolved from the directory where the run started.

## Rules

- `#include` only these headers, and `"runtime.hpp"`: algorithm any array bitset cctype
  charconv climits cmath cstddef cstdint cstring cstdlib deque functional initializer_list
  iomanip iterator limits list map memory numeric optional queue regex set sstream stack
  stdexcept string string_view tuple type_traits unordered_map unordered_set utility variant
  vector. No other preprocessor directives (`#define`, `#if`, `#pragma`, ...).
- Never use streams (`std::cout`, `std::cerr`, `std::ifstream`, ...), C stdio, `system`,
  `getenv`, `time`, `rand`, `exit`, `<chrono>`, `<random>`, `<thread>`, or `<filesystem>`.
- Need the time, an environment variable, or randomness? Get it through `run_command`
  (for example `run_command({"date", "+%F"})`) so it is recorded and replayed.
- No `catch (...)`. `catch (const std::exception&)` is fine.
- Do not call helpers from destructors or other cleanup code. `ask` and `fail` leave the
  workflow by throwing, and a throw from a destructor terminates the program.
- No raw string literals (`R"(...)"`), no inline assembly.
- Do not name your own functions after denied C calls (`open`, `read`, `write`, `close`,
  `time`, `remove`, `link`, `stat`, `wait`, ...); `check` rejects the call by name.
  `std::remove(` is rejected too (it is also the C file call); use `std::remove_if`.
- Prefer `std::map` and `std::set` over the unordered containers so iteration order is
  obvious to a reviewer.

## Shape

```cpp
#include "runtime.hpp"
#include <sstream>
#include <vector>

std::string workflow() {
  // 手順 1: 引数を行に分ける
  std::vector<std::string> lines;
  std::istringstream in(dullmify::args());
  for (std::string line; std::getline(in, line);)
    if (!line.empty()) lines.push_back(line);
  // 手順 2: 行ごとに地名を聞く
  std::string report = "places:";
  for (const std::string& line : lines)
    report += " " + dullmify::ask("この文に書かれた地名を一つ答えてください", line);
  // 手順 3: 結果を書く
  dullmify::write_file("places.txt", report + "\n");
  return report;
}
```
