#!/bin/sh
# Assembles a dullmified skill.
#   sh assemble.sh <lang> <source SKILL.md> <outdir> <workflow file>
# <outdir>/SKILL.md and <outdir>/scripts/ belong to this script; everything
# else in <outdir> is left alone. The workflow file is normally
# <outdir>/scripts/workflow.<ext>; it is read before that directory is replaced.
# Checks the workflow with langs/<lang>/check. On failure prints the reasons
# and removes <outdir>/SKILL.md and <outdir>/scripts/. On success writes both.
set -u
dir=$(cd "$(dirname "$0")" && pwd)
if [ $# -ne 4 ]; then
  echo "usage: sh assemble.sh <lang> <source> <outdir> <workflow file>" >&2
  exit 2
fi
lang=$1; source=$2; outdir=$3; workflow=$4
langdir="$dir/langs/$lang"
if [ ! -f "$langdir/GUIDE.md" ]; then
  echo "unsupported language: $lang (available: $(ls "$dir/langs" | tr '\n' ' '))" >&2
  exit 1
fi
[ -f "$source" ] || { echo "source not found: $source" >&2; exit 1; }
[ "$(head -n 1 "$source")" = "---" ] || { echo "source has no frontmatter: $source" >&2; exit 1; }
end=$(sed -n '2,${/^---$/{=;q;}}' "$source")
[ -n "$end" ] || { echo "source frontmatter is not closed: $source" >&2; exit 1; }
ext=$(cat "$langdir/ext")
[ -f "$workflow" ] || { echo "workflow file not found: $workflow" >&2; exit 1; }

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
cp "$workflow" "$tmp/workflow.$ext"

reject() { # reason
  echo "$1" >&2
  rm -rf "$outdir/SKILL.md" "$outdir/scripts"
  exit 1
}
[ -s "$tmp/workflow.$ext" ] || reject "empty workflow; nothing written"
sh "$langdir/check" "$tmp/workflow.$ext" || reject "workflow rejected; nothing written"

# Thin SKILL.md: the source frontmatter minus allowed-tools, plus the launcher
# approval, then the fixed template body.
{
  echo '---'
  sed -n "2,$((end - 1))p" "$source" | awk '
    /^allowed-tools:/ { skip = 1; next }
    skip && /^[[:space:]]/ { next }
    { skip = 0; print }'
  echo 'allowed-tools: Write Bash(sh ${CLAUDE_SKILL_DIR}/scripts/run *)'
  echo '---'
  cat "$dir/templates/thin-skill.md"
} > "$tmp/SKILL.md"

mkdir -p "$outdir" || exit 1
rm -rf "$outdir/SKILL.md" "$outdir/scripts"
mkdir "$outdir/scripts" \
  && cp "$tmp/SKILL.md" "$outdir/SKILL.md" \
  && cp "$langdir/run" "$langdir"/runtime.* "$outdir/scripts/" \
  && cp "$tmp/workflow.$ext" "$outdir/scripts/workflow.$ext" \
  || reject "could not write $outdir; nothing left there"
echo "assembled: $outdir"
(cd "$outdir" && find SKILL.md scripts -type f | sort | sed 's/^/  /')
