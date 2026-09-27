
Run the workflow program bundled with this skill and relay its questions.

The launcher is `scripts/run` in the same directory as this SKILL.md. Call it with `sh` and its absolute path as a single command: no `cd`, no pipes, no other wrappers. Write the files it asks for with the file-writing tool, verbatim, never through the shell.

1. Start: `sh <skill dir>/scripts/run start`. It prints `{"run":…,"write":…}`. Write the arguments given to this skill to the `write` path (an empty file if there are none), then continue.
2. Continue: `sh <skill dir>/scripts/run continue <run>`. Read the last line of stdout as JSON and act on it.
   - `{"run":…,"ask":N,"prompt":…,"input":…,"write":…}`: answer the prompt about the input. If the prompt tells you to use a tool (read a file, ask the user), do that to find the answer. Write the answer to the `write` path, then continue.
   - `{"done":true,"report":…}`: show the report to the user verbatim and stop.
   - `{"failed":…}`: report the failure to the user verbatim and stop. Do not retry, work around, or fix anything.
   - No JSON, exit code 2: the call itself was wrong, or a file is still missing. Do what stderr says, then continue.
   - Anything else (no JSON, another exit code): show stdout and stderr to the user verbatim and stop.

Between calls, do nothing besides answering the question. If a call returns before it has finished (for example, it was moved to the background), wait until it finishes and read its final output; if there is none, continue again.
