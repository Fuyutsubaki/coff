#!/usr/bin/env bash
# 静的検査: 配布物 skills/ が claude-code（.claude/skills/）と codex（.agents/skills/）の
# 両方の配置で成立することを確かめる。
#   1. skills/*/SKILL.md の本文に claude 固有の記述が無い。
#   2. 本文中のバッククォート付き `.../SKILL.md` 参照が、参照元 SKILL.md のディレクトリ基準で
#      両配置とも解決する（`gh skill install --from-local` で一時 repo に導入して確認）。
# 本文 = フェンスコードブロックの外。< * $ を含む参照（プレースホルダ）は対象外。
set -uo pipefail
command -v gh >/dev/null || { echo "gh が見つからない"; exit 2; }
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

# フェンス内の行は空行に置き換え、報告する行番号を元ファイルと一致させる。
prose() { awk '/^[[:space:]]*```/ { f = !f; print ""; next } f { print ""; next } 1' "$1"; }

for f in "$root"/skills/*/SKILL.md; do
  rel=${f#"$root"/}
  p=$(prose "$f")
  grep -nE '`[^`<*$]*\.claude/skills/[^`<*$]*SKILL\.md`' <<<"$p" | sed "s#^#FAIL: $rel: .claude/skills/ への参照: #" && fail=1
  grep -nE 'AskUserQuestion' <<<"$p" | sed "s#^#FAIL: $rel: claude のツール名: #" && fail=1
  grep -nE '(^|[^A-Za-z0-9_./])/coff-[a-z-]+' <<<"$p" | sed "s#^#FAIL: $rel: スラッシュ記法の呼び出し: #" && fail=1
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
      || { echo "FAIL: [$agent] $name の導入に失敗"; fail=1; }
  done
  for f in "$d"/$dir/*/SKILL.md; do
    [ -e "$f" ] || { echo "FAIL: [$agent] $dir に何も導入されていない"; fail=1; break; }
    rel=${f#"$d"/}
    while read -r ref; do
      [ -n "$ref" ] || continue
      [ -e "$(dirname "$f")/$ref" ] || { echo "FAIL: [$agent] $rel -> $ref が見つからない"; fail=1; }
    done < <(prose "$f" | grep -oE '`[^`<*$]*/[^`<*$]*SKILL\.md`' | tr -d '`' | sort -u)
  done
done

if [ "$fail" = 0 ]; then echo "PASS: static"; else echo "FAIL: static"; fi
exit "$fail"
