#!/bin/sh

# workflow の検査に通ったときだけ、薄い skill と実行用ファイルを組み立てる。
set -u

skill_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || {
  echo "coff-dullmify の場所を解決できません" >&2
  exit 2
}

if [ "${1-}" = "--discard" ]; then
  [ "$#" -eq 2 ] || { echo "--discard には出力先を一つ指定してください" >&2; exit 2; }
  outdir=$2
  [ -n "$outdir" ] && [ "$outdir" != "/" ] || { echo "片付ける出力先が不正です" >&2; exit 2; }
  rm -f -- "$outdir/SKILL.md"
  rm -rf -- "$outdir/scripts"
  exit 0
fi

[ "$#" -eq 3 ] || {
  echo "使い方: sh assemble.sh <ruby|cpp> <source> <outdir>" >&2
  exit 2
}

language=$1
source_file=$2
outdir=$3
language_dir=$skill_dir/langs/$language
[ -f "$source_file" ] || { echo "ソースを読めません: $source_file" >&2; exit 2; }

case "$language" in
  ruby) workflow=$outdir/scripts/workflow.rb ;;
  cpp) workflow=$outdir/scripts/workflow.cpp ;;
  *) echo "対応していない言語です: $language（対応: ruby cpp）" >&2; exit 2 ;;
esac
[ -f "$workflow" ] || { echo "workflow がありません: $workflow" >&2; exit 1; }

# 構文エラーの出力は、修正に使えるようそのまま呼び出し元へ返す。
sh "$language_dir/check" "$workflow" || exit 1

for file in "$language_dir"/*; do
  name=$(basename -- "$file")
  case "$name" in
    GUIDE.md|check) continue ;;
  esac
  cp -- "$file" "$outdir/scripts/$name" || exit 1
done

awk '
  NR == 1 {
    if ($0 != "---") exit 3
    print
    front = 1
    next
  }
  front {
    if ($0 == "---") {
      print "allowed-tools: Write Bash(sh ${CLAUDE_SKILL_DIR}/scripts/run *)"
      print
      closed = 1
      exit
    }
    if (skipping) {
      if ($0 ~ /^[[:space:]]/ || $0 ~ /^-[[:space:]]/) next
      skipping = 0
    }
    if ($0 ~ /^allowed-tools:[[:space:]]*/) {
      skipping = 1
      next
    }
    print
  }
  END { if (!closed) exit 4 }
' "$source_file" > "$outdir/SKILL.md" || {
  echo "ソースの frontmatter を読めません" >&2
  exit 1
}
printf '\n' >> "$outdir/SKILL.md"
cat "$skill_dir/templates/thin-skill.md" >> "$outdir/SKILL.md" || exit 1

echo "組み立てました: $outdir"
