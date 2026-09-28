#!/bin/sh

# <outdir>/scripts/ に書かれた workflow を検査し、同梱ランタイムと薄い SKILL.md を足して skill を組み立てる。
set -u

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || {
  echo "coff-dullmify の場所を解決できません" >&2
  exit 2
}

discard() {
  rm -rf "$1/SKILL.md" "$1/scripts"
}

if [ "${1:-}" = --discard ]; then
  if [ "$#" -ne 2 ]; then
    echo "使い方: sh assemble.sh --discard <outdir>" >&2
    exit 2
  fi
  discard "$2"
  exit 0
fi

if [ "$#" -ne 3 ]; then
  echo "使い方: sh assemble.sh <lang> <source> <outdir>" >&2
  exit 2
fi

lang=$1
source_file=$2
outdir=$3
lang_dir=$script_dir/langs/$lang

if [ ! -f "$lang_dir/check" ]; then
  echo "対応していない言語です: $lang" >&2
  exit 1
fi
if [ ! -f "$source_file" ]; then
  echo "skill ソースがありません: $source_file" >&2
  exit 1
fi

# workflow は LLM が <outdir>/scripts/workflow.<拡張子> に 1 つだけ書く。
set -- "$outdir"/scripts/workflow.*
if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then
  echo "workflow がありません（$outdir/scripts/workflow.<拡張子> に 1 つだけ書いてください）" >&2
  discard "$outdir"
  exit 1
fi
workflow_file=$1

if ! sh "$lang_dir/check" "$workflow_file"; then
  echo "workflow の構文検査に失敗しました（理由は上のコンパイラの出力）" >&2
  discard "$outdir"
  exit 1
fi

# GUIDE.md と check 以外の同梱ファイル（起動スクリプト、ランタイム、ライブラリとそのライセンス）を写す。
for file in "$lang_dir"/*; do
  case ${file##*/} in
    GUIDE.md | check) ;;
    *) cp "$file" "$outdir/scripts/" || { discard "$outdir"; exit 2; } ;;
  esac
done

# frontmatter を写し、allowed-tools（続くリストの行も含む）を起動スクリプトの許可に置き換える。
if ! awk '
  NR == 1 && $0 == "---" { print; frontmatter = 1; next }
  frontmatter && $0 == "---" {
    print "allowed-tools: Write Bash(sh ${CLAUDE_SKILL_DIR}/scripts/run *)"
    print "---"
    found_end = 1
    exit
  }
  frontmatter && skipping && /^([[:space:]]|-)/ { next }
  frontmatter { skipping = 0 }
  frontmatter && /^allowed-tools:/ { skipping = 1; next }
  frontmatter { print }
  END { if (!frontmatter || !found_end) exit 1 }
' "$source_file" >"$outdir/SKILL.md.tmp"; then
  echo "skill ソースの frontmatter を読めません" >&2
  rm -f "$outdir/SKILL.md.tmp"
  discard "$outdir"
  exit 1
fi
cat "$script_dir/templates/thin-skill.md" >>"$outdir/SKILL.md.tmp" && mv "$outdir/SKILL.md.tmp" "$outdir/SKILL.md" || {
  rm -f "$outdir/SKILL.md.tmp"
  discard "$outdir"
  exit 2
}

echo "薄い skill を組み立てました: $outdir"
