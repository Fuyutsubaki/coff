#!/usr/bin/env bash
# Static check: the distributed coff skills (skills/) work in both the
# claude-code (.claude/skills/) and codex (.agents/skills/) layouts.
#   1. No claude-specific text in the prose of skills/*/SKILL.md.
#   2. Every backticked `.../SKILL.md` reference in the prose resolves relative
#      to the referring SKILL.md's directory, in both layouts (installed with
#      `gh skill install --from-local`).
# Prose = everything outside fenced code blocks. References containing < * $
# (placeholders) are ignored.
set -uo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

# Fenced lines become blank lines so reported line numbers match the file.
prose() { awk '/^[[:space:]]*```/ { f = !f; print ""; next } f { print ""; next } 1' "$1"; }

for f in "$root"/skills/*/SKILL.md; do
  rel=${f#"$root"/}
  p=$(prose "$f")
  grep -nE '`[^`<*$]*\.claude/skills/[^`<*$]*SKILL\.md`' <<<"$p" | sed "s#^#FAIL: $rel: .claude/skills/ reference: #" && fail=1
  grep -nE 'AskUserQuestion' <<<"$p" | sed "s#^#FAIL: $rel: claude tool name: #" && fail=1
  grep -nE '`/coff-[a-z-]+' <<<"$p" | sed "s#^#FAIL: $rel: slash invocation: #" && fail=1
done

for agent in claude-code codex; do
  case $agent in
    claude-code) dir=.claude/skills ;;
    codex) dir=.agents/skills ;;
  esac
  d="$tmp/$agent"
  mkdir -p "$d" && git -C "$d" init -q
  for s in "$root"/skills/*/; do
    name=$(basename "$s")
    (cd "$d" && gh skill install --from-local "$root" "$name" --agent "$agent" --scope project >/dev/null 2>&1) \
      || { echo "FAIL: [$agent] install $name"; fail=1; }
  done
  for f in "$d"/$dir/*/SKILL.md; do
    [ -e "$f" ] || { echo "FAIL: [$agent] nothing installed under $dir"; fail=1; break; }
    rel=${f#"$d"/}
    while read -r ref; do
      [ -n "$ref" ] || continue
      [ -e "$(dirname "$f")/$ref" ] || { echo "FAIL: [$agent] $rel -> $ref not found"; fail=1; }
    done < <(prose "$f" | grep -oE '`[^`<*$]*/[^`<*$]*SKILL\.md`' | tr -d '`' | sort -u)
  done
done

if [ "$fail" = 0 ]; then echo "PASS: static"; else echo "FAIL: static"; fi
exit "$fail"
