---
name: coff-issue-list
description: List the issues under `issue/`. Argument is `open` (default) | `done` | `all`.
license: MIT
allowed-tools: Bash(awk *)
---

Listing of `issue/`. Present it as is.

```!
awk -v want="$ARGUMENTS" '
BEGIN {
  if (want == "") want = "open"
  print "| 状態 | パス | タイトル | 要約 |"
  print "|---|---|---|---|"
}
function flush() {
  if (f != "" && (want == "all" || want == st)) {
    gsub(/\|/, "\\|", t); gsub(/\|/, "\\|", s)
    printf "| %s | %s | %s | %s |\n", st, f, t, s
    n++
  }
}
FNR == 1 { flush(); f = FILENAME; st = "open"; t = ""; s = ""; fm = ($(0) == "---") }
fm {
  if (FNR > 1 && $(0) == "---") { fm = 0; next }
  if (match($(0), /^status:[ \t]*[a-z]+/)) { st = substr($(0), RSTART, RLENGTH); sub(/^status:[ \t]*/, "", st) }
  next
}
t == "" && /^# / { t = substr($(0), 3); next }
t != "" && s == "" && NF && !/^#/ { s = $(0) }
END { flush(); printf "\n%d 件\n", n + 0 }
' issue/*/*/*.md 2>/dev/null
```
<!--{"src":".coff/src/coff-issue-list.skill.md","md5":"f5c4b4ca84e49ad588cb5145aefc5b93"} -->
