---
name: coff-issue-list
description: `issue/` の issue を一覧する。引数は `open`（既定）| `done` | `all`。
license: MIT
coff-dist: true
allowed-tools: Bash(awk *)
---

<!--
一覧に判断は要らないので、LLM の手順ではなく埋め込みコマンドで出す。埋め込みでは `$0` `$1` が N 番目の引数に置換されるため、awk の `$0` は `$(0)` と書く。
-->

`issue/` の一覧。そのまま提示する。

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
