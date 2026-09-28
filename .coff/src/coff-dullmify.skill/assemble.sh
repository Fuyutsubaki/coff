#!/bin/sh

# 検査済みの workflow と同梱ランタイムから、薄い skill を組み立てる。
set -u

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || {
  echo "coff-dullmify の場所を解決できません" >&2
  exit 2
}

discard() {
  target=$1
  if [ -e "$target/SKILL.md" ]; then
    find "$target/SKILL.md" -depth -delete
  fi
  if [ -e "$target/scripts" ]; then
    find "$target/scripts" -depth -delete
  fi
}

if [ "${1:-}" = --discard ]; then
  if [ "$#" -ne 2 ]; then
    echo "使い方: sh assemble.sh --discard <outdir>" >&2
    exit 2
  fi
  discard "$2"
  exit 0
fi

if [ "$#" -ne 4 ]; then
  echo "使い方: sh assemble.sh <lang> <source> <outdir> <workflow>" >&2
  exit 2
fi

lang=$1
source_file=$2
outdir=$3
workflow_file=$4
lang_dir=$script_dir/langs/$lang

if [ ! -f "$lang_dir/GUIDE.md" ]; then
  supported=$(find "$script_dir/langs" -mindepth 2 -maxdepth 2 -name GUIDE.md -print | sed 's:/GUIDE.md$::; s:.*/::' | sort | tr '\n' ' ')
  echo "対応していない言語です: $lang（対応言語: $supported）" >&2
  exit 1
fi
if [ ! -f "$source_file" ]; then
  echo "skill ソースがありません: $source_file" >&2
  exit 1
fi
if [ ! -f "$workflow_file" ]; then
  echo "workflow がありません: $workflow_file" >&2
  discard "$outdir"
  exit 1
fi

case $lang in
  ruby)
    workflow_name=workflow.rb
    runtime_name=runtime.rb
    ;;
  cpp)
    workflow_name=workflow.cpp
    runtime_name=runtime.hpp
    ;;
  *)
    echo "言語の組み立て規約がありません: $lang" >&2
    exit 1
    ;;
esac

if ! sh "$lang_dir/check" "$workflow_file"; then
  echo "workflow の構文検査に失敗しました" >&2
  discard "$outdir"
  exit 1
fi

temporary=$(mktemp -d "${TMPDIR:-/tmp}/coff-dullmify-assemble.XXXXXX") || {
  echo "組み立て用の一時ディレクトリを作成できません" >&2
  exit 2
}
trap 'find "$temporary" -depth -delete 2>/dev/null || true' EXIT HUP INT TERM
mkdir -p "$temporary/scripts" || exit 2

cp "$lang_dir/run" "$temporary/scripts/run" || exit 2
cp "$lang_dir/$runtime_name" "$temporary/scripts/$runtime_name" || exit 2
cp "$workflow_file" "$temporary/scripts/$workflow_name" || exit 2
if [ "$lang" = cpp ]; then
  cp "$lang_dir/json.hpp" "$temporary/scripts/json.hpp" || exit 2
fi

if ! awk '
  NR == 1 && $0 == "---" { print; frontmatter = 1; next }
  frontmatter && $0 == "---" {
    print "allowed-tools: Write Bash(sh ${CLAUDE_SKILL_DIR}/scripts/run *)"
    print "---"
    found_end = 1
    exit
  }
  frontmatter && $0 !~ /^allowed-tools:[[:space:]]*/ { print }
  END { if (!frontmatter || !found_end) exit 1 }
' "$source_file" >"$temporary/SKILL.md"; then
  echo "skill ソースの frontmatter を読めません" >&2
  discard "$outdir"
  exit 1
fi
cat "$script_dir/templates/thin-skill.md" >>"$temporary/SKILL.md" || exit 2

mkdir -p "$outdir" || {
  echo "出力先を作成できません: $outdir" >&2
  exit 2
}
discard "$outdir"
mv "$temporary/scripts" "$outdir/scripts" || exit 2
mv "$temporary/SKILL.md" "$outdir/SKILL.md" || exit 2

echo "薄い skill を組み立てました: $outdir"
