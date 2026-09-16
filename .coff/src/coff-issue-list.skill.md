---
name: coff-issue-list
description: `issue/` の issue を状態、パス、タイトルで一覧する。引数は `open`（既定）| `done` | `all`。
license: MIT
coff-dist: true
allowed-tools: Bash(awk *)
---

<!--
一覧に判断は要らないので、手順は「コマンドを実行して出力を出す」だけにする。claude 固有の `!` フェンス（埋め込み展開）は使わず、どの agent でも同じ手順で動く普通の bash ブロックにする（issue/2026/09/1515-drop-claude-dependency.md の判断）。agent によっては本文の `$0` `$1` が N 番目の引数に置換されるため、awk の `$0` は `$(0)` と書く。グロブが空だと gawk は致命エラーで END を実行しないため、`ls` の失敗時は `/dev/null` を渡す。BEGIN の `exit` 後も END は走るので、END 側で引数を再確認している。
-->

`issue/` の一覧。次のコマンドを実行し、出力をそのまま提示する。`$ARGUMENTS` は与えられた引数（無ければ空）。

```bash
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
/^```/ { fence = !fence; next }
fence { next }
t == "" && /^# / { t = substr($(0), 3) }
END { if (want == "open" || want == "done" || want == "all") { flush(); printf "\n%d 件\n", n } }
' $(ls issue/*/*/*.md 2>/dev/null || echo /dev/null)
```
