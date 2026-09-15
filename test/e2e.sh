#!/usr/bin/env bash
# E2E: run coff-issue-done non-interactively through claude and codex, each in
# its own layout, and check that it follows the relative reference to
# coff-detail-issue and flips the fixture issue to `status: done`.
# Requires both CLIs to be installed and authenticated.
set -uo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0
fixture=issue/2026/01/0101-fixture.md

setup() { # $1 = agent
  local d="$tmp/$1"
  mkdir -p "$d/$(dirname "$fixture")" && git -C "$d" init -q
  for n in coff-detail-issue coff-issue-done; do
    (cd "$d" && gh skill install --from-local "$root" "$n" --agent "$1" --scope project >/dev/null 2>&1) \
      || { echo "FAIL: [$1] install $n"; fail=1; }
  done
  printf -- '---\nstatus: open\n---\n# e2e fixture\n' > "$d/$fixture"
  git -C "$d" add -A && git -C "$d" -c user.name=e2e -c user.email=e2e@example.com commit -qm fixture
}

check() { # $1 = agent
  if head -3 "$tmp/$1/$fixture" | grep -q '^status: done$'; then
    echo "PASS: [$1] coff-issue-done"
  else
    echo "FAIL: [$1] coff-issue-done (log: $tmp/$1.log)"; tail -20 "$tmp/$1.log"; fail=1
  fi
}

setup claude-code
(cd "$tmp/claude-code" && claude -p "/coff-issue-done $fixture" --allowedTools 'Skill,Bash,Read,Edit,Write' >"$tmp/claude-code.log" 2>&1)
check claude-code

setup codex
(cd "$tmp/codex" && codex exec --skip-git-repo-check --sandbox workspace-write "\$coff-issue-done $fixture" >"$tmp/codex.log" 2>&1)
check codex

exit "$fail"
