---
name: coff-issue-list
description: List the issues under `issue/` by status, path, and title. Argument is `open` (default) | `done` | `all`.
license: MIT
allowed-tools: Bash(awk *)
---

Listing of `issue/`. Present it as is.

```!
awk -v want="$ARGUMENTS" '
BEGIN {
  if (want == "") want = "open"
  if (want != "open" && want != "done" && want != "all") { print "引数は open | done | all のいずれか: " want; exit 1 }
  print "| 状態 | パス | タイトル |"
  print "|---|---|---|"
}
function flush() {
  if (f != "" && (want == "all" || want == st)) { gsub(/\|/, "\\|", t); printf "| %s | %s | %s |\n", st, f, t; n++ }
}
FNR == 1 { flush(); f = FILENAME; st = "open"; t = ""; fm = ($(0) == "---") }
fm {
  if (FNR > 1 && $(0) == "---") { fm = 0; next }
  if (match($(0), /^status:[ \t]*[a-z]+/)) { st = substr($(0), RSTART, RLENGTH); sub(/^status:[ \t]*/, "", st) }
  next
}
t == "" && /^# / { t = substr($(0), 3) }
END { if (want == "open" || want == "done" || want == "all") { flush(); printf "\n%d 件\n", n } }
' $(ls issue/*/*/*.md 2>/dev/null || echo /dev/null)
```
<!--{"src":".coff/src/coff-issue-list.skill.md","md5":"03b8b757f4e0b50742bd4ec35170dd8f"} -->
