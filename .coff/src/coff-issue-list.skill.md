---
name: coff-issue-list
description: `issue/` の issue を一覧する。引数は `open`（既定）| `done` | `all`。状態、パス、タイトル、要約の 1 行目を表で出す。
license: MIT
coff-dist: true
---

<!--
一覧は都度生成する。一覧ファイル（issue/README.md など）を置く案は陳腐化するため却下した（issue/2026/09/1413-issue-template-for-human-reader.md の判断）。状態の解釈は coff-detail-issue に従う。
-->

## 手順

1. 引数を読む。`open` / `done` / `all` のいずれかで、無ければ `open`。
2. `issue/` 配下の `*.md` をパス順に走査し、各ファイルから状態、タイトル、要約を取る。状態の解釈は `.claude/skills/coff-detail-issue/SKILL.md` の状態仕様に従う（frontmatter または `status` が無ければ `open`）。要約はタイトルより後で最初に現れる、見出しでも空行でもない行とする（新テンプレートではタイトル直下の段落、旧テンプレートでは最初の節の 1 行目になる）。

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

3. 引数で絞り、Markdown の表（状態 | パス | タイトル | 要約）で出す。末尾に件数を添える。要約が取れない issue は要約欄を空にし、警告はしない。 <!-- 旧テンプレートや手書き issue を壊さないため -->

## 適用範囲

- 読み取りのみ。issue ファイルを変更しない。
