# Writing a workflow in Ruby

File name: `workflow.rb`.

The runtime loads `workflow.rb` and calls `workflow`, which returns the report as a String.
The program is re-run from the top after every answer, so control flow must depend only on
`args`, answers, and helper results. Every interaction with the outside world goes through
the helpers below; anything else is a bug and `check` rejects it.

## Helpers

- `args` → String. The arguments given to the skill, verbatim. Split them yourself.
- `ask(prompt, input = "")` → String. Asks the LLM. `prompt` says what to answer and how;
  `input` is the data to look at.
- `run_command(argv, stdin = nil)` → result with `.status`, `.out`, `.err`.
  `argv` is an Array; no shell is involved. A non-zero status does not raise.
- `read_file(path)` → String, or nil when the file does not exist.
- `write_file(path, content)`. Creates parent directories.
- `fail_run(reason)`. Stops the run as failed.

Relative paths are resolved from the directory where the run started.

## Rules

- Never write to stdout or stderr (`puts`, `print`, `p`, `warn`, `$stdout`, ...).
- Never touch `File`, `Dir`, `IO`, `ENV`, `Time`, `rand`, `system`, backticks, `require`,
  `eval`, `send`, `exit`, or `rescue Exception`. `rescue => e` (StandardError) is fine.
- Need the time, an environment variable, or randomness? Get it through `run_command`
  (for example `run_command(["date", "+%F"])`) so it is recorded and replayed.
- Do not use names from the deny list as your own identifiers (for example a variable
  called `p`); `check` rejects by name. Symbols and hash labels (`:p`, `method:`) are fine.
- Available without `require`: the core library plus `set` and `json`.
- `Object#hash`, `object_id`, `shuffle`, and `sample` differ between runs; they are rejected.

## Shape

```ruby
# 手順 1: 引数を行に分ける
def workflow
  lines = args.split("\n").reject(&:empty?)
  # 手順 2: 行ごとに地名を聞く
  places = lines.map { |line| ask("この文に書かれた地名を一つ答えてください", line).strip }
  # 手順 3: 結果を書く
  write_file("places.txt", places.join("\n") + "\n")
  "places: #{places.join(', ')}"
end
```
