---
name: coff-issue-list
description: List the issues under `issue/`. Argument is `open` (default) | `done` | `all`. Prints a table of status, path, title, and the first line of the summary.
license: MIT
---

## Procedure

1. Read the argument: one of `open` / `done` / `all`; `open` if absent.
2. Walk the `*.md` files under `issue/` in path order and take each file's status, title, and summary. Interpret status per the status spec in `.claude/skills/coff-detail-issue/SKILL.md` (`open` if there is no frontmatter or no `status`). The summary is the first line after the title that is neither a heading nor blank (the paragraph under the title in the new template; the first line of the first section in the old ones).

   ```bash
   find issue -name '*.md' | sort | while read -r f; do
     status=open
     if [ "$(head -1 "$f")" = "---" ]; then
       s=$(sed -n '2,/^---$/p' "$f" | sed -n 's/^status:[[:space:]]*\([a-z]*\).*/\1/p' | head -1)
       [ -n "$s" ] && status=$s
     fi
     title=$(grep -m1 '^# ' "$f" | sed 's/^# //')
     summary=$(awk '/^# /{f=1; next} f && NF && !/^#/ {print; exit}' "$f")
     printf '%s\t%s\t%s\t%s\n' "$status" "$f" "$title" "$summary"
   done
   ```

3. Filter by the argument and print a Markdown table (status | path | title | summary), followed by the count. Leave the summary cell empty for issues where none can be extracted; do not warn.

## Scope

- Read-only. Never modify issue files.
<!--{"src":".coff/src/coff-issue-list.skill.md","md5":"0a885785bd5ffdd0a6ea5230cc729afd"} -->
