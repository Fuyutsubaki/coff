#!/usr/bin/env bash
# E2E: run coff-issue-done non-interactively through claude and codex, each in
# its own layout, and check that it follows the relative reference to
# coff-detail-issue and flips the fixture issue to `status: done`.
# Requires both CLIs to be installed and authenticated.
set -uo pipefail
for c in gh claude codex; do command -v "$c" >/dev/null || { echo "missing: $c"; exit 2; }; done
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
fail=0
trap '[ "$fail" = 0 ] && rm -rf "$tmp"' EXIT   # keep the logs on failure
fixture=issue/2026/01/0101-fixture.md

setup() { # $1 = agent
  local d="$tmp/$1" ok=1
  mkdir -p "$d/$(dirname "$fixture")" && git -C "$d" init -q
  for n in coff-detail-issue coff-issue-done; do
    (cd "$d" && gh skill install --from-local "$root" "$n" --agent "$1" --scope project >/dev/null 2>&1) \
      || { echo "FAIL: [$1] install $n"; fail=1; ok=0; }
  done
  printf -- '---\nstatus: open\n---\n# e2e fixture\n' > "$d/$fixture"
  [ "$ok" = 1 ]
}

check() { # $1 = agent
  if head -3 "$tmp/$1/$fixture" | grep -q '^status: done$'; then
    echo "PASS: [$1] coff-issue-done"
  else
    echo "FAIL: [$1] coff-issue-done (log kept: $tmp/$1.log)"; tail -20 "$tmp/$1.log"; fail=1
  fi
}

if setup claude-code; then
  (cd "$tmp/claude-code" && claude -p "/coff-issue-done $fixture" --allowedTools 'Skill,Bash,Read,Edit,Write' </dev/null >"$tmp/claude-code.log" 2>&1)
  check claude-code
fi

if setup codex; then
  (cd "$tmp/codex" && codex exec --skip-git-repo-check --sandbox workspace-write "\$coff-issue-done $fixture" </dev/null >"$tmp/codex.log" 2>&1)   # codex reads stdin when it is not a TTY
  check codex
fi

exit "$fail"
