#!/bin/sh

# workflow の検査に通ったときだけ、薄い skill と実行用ファイルを組み立てる。
set -u

skill_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || {
  echo "coff-dullmify の場所を解決できません" >&2
  exit 2
}

# <outdir> は dullmify 専用とし、dullmify が書く SKILL.md と scripts/ 以外があれば触れない。
only_dullmify_output() {
  for entry in "$1"/* "$1"/.[!.]* "$1"/..?*; do
    [ -e "$entry" ] || [ -L "$entry" ] || continue
    case "${entry##*/}" in
      SKILL.md|scripts) ;;
      *) echo "出力先に dullmify が書いたもの以外があります: $entry" >&2; return 1 ;;
    esac
  done
}

if [ "${1-}" = "--discard" ]; then
  outdir=${2-}
  [ -d "$outdir" ] || exit 0
  only_dullmify_output "$outdir" || exit 2
  rm -rf -- "$outdir"
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

# 対応言語は langs/<lang>/GUIDE.md の有無で決める（SKILL.md と同じ基準）。
case "$language" in
  ''|.*|*/*) supported=false ;;
  *) [ -f "$language_dir/GUIDE.md" ] && supported=true || supported=false ;;
esac
if [ "$supported" = false ]; then
  echo "対応していない言語です: $language（対応: $(cd "$skill_dir/langs" && echo *)）" >&2
  exit 2
fi
# workflow の名前は GUIDE が定め、LLM が scripts/ に書く workflow.* はそれ 1 つだけである。
set -- "$outdir"/scripts/workflow.*
[ "$#" -eq 1 ] && [ -f "$1" ] || { echo "workflow がありません: $outdir/scripts/workflow.*" >&2; exit 1; }
workflow=$1
only_dullmify_output "$outdir" || exit 2

# 構文エラーの出力は、修正に使えるようそのまま呼び出し元へ返す。
sh "$language_dir/check" "$workflow" || exit 1

for file in "$language_dir"/*; do
  name=$(basename -- "$file")
  case "$name" in
    GUIDE.md|check) continue ;;
  esac
  cp -- "$file" "$outdir/scripts/$name" || exit 1
done
cp -- "$skill_dir/templates/run" "$outdir/scripts/run" || exit 1

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
