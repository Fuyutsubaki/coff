#!/usr/bin/env bash
# E2E: claude と codex をそれぞれの配置で非対話に起動して coff-issue-done を実行し、
# coff-detail-issue への相対参照を辿って fixture issue を `status: done` にすることを確かめる。
# 両 CLI が導入・認証済みであることが前提。
set -uo pipefail
for c in gh claude codex; do command -v "$c" >/dev/null || { echo "$c が見つからない"; exit 2; }; done
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
fail=0
trap '[ "$fail" = 0 ] && rm -rf "$tmp"' EXIT   # 失敗時はログを残す
fixture=issue/2026/01/0101-fixture.md

setup() { # $1 = agent 名
  local d="$tmp/$1" ok=1
  mkdir -p "$d/$(dirname "$fixture")" && git -C "$d" init -q
  for n in coff-detail-issue coff-issue-done; do
    (cd "$d" && gh skill install --from-local "$root" "$n" --agent "$1" --scope project >/dev/null 2>&1) \
      || { echo "FAIL: [$1] $n の導入に失敗"; fail=1; ok=0; }
  done
  printf -- '---\nstatus: open\n---\n# e2e fixture\n' > "$d/$fixture"
  [ "$ok" = 1 ]
}

check() { # $1 = agent 名
  if head -3 "$tmp/$1/$fixture" | grep -q '^status: done$'; then
    echo "PASS: [$1] coff-issue-done"
  else
    echo "FAIL: [$1] coff-issue-done（ログ: $tmp/$1.log）"; tail -20 "$tmp/$1.log"; fail=1
  fi
}

if setup claude-code; then
  (cd "$tmp/claude-code" && claude -p "/coff-issue-done $fixture" --allowedTools 'Skill,Bash,Read,Edit,Write' </dev/null >"$tmp/claude-code.log" 2>&1)
  check claude-code
fi

if setup codex; then
  (cd "$tmp/codex" && codex exec --skip-git-repo-check --sandbox workspace-write "\$coff-issue-done $fixture" </dev/null >"$tmp/codex.log" 2>&1)   # codex は stdin が端末でないと入力を待つので閉じる
  check codex
fi

exit "$fail"
