#!/bin/sh
# Tests for the dullmify runtimes and check scripts. The LLM's role is played
# by fixed answers. Exit code 0 means every test passed.
#   sh .coff/test/coff-dullmify/run-tests.sh [ruby|cpp]
set -u
here=$(cd "$(dirname "$0")" && pwd)
skill=$(cd "$here/../../src/coff-dullmify.skill" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export TMPDIR="$work/tmp"
mkdir -p "$TMPDIR"
fails=0
total=0

pass() { total=$((total + 1)); echo "ok   $1"; }
fail() { total=$((total + 1)); fails=$((fails + 1)); echo "FAIL $1${2:+ -- $2}"; }
check() { # name, expected, actual
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "expected [$2] got [$3]"; fi
}
contains() { # name, needle, haystack
  case "$3" in *"$2"*) pass "$1" ;; *) fail "$1" "missing [$2] in [$3]" ;; esac
}
field() { # json line, field name (string value)
  printf '%s\n' "$1" | tail -n 1 | sed -n "s/.*\"$2\":\"\([^\"]*\)\".*/\1/p"
}
nfield() { # json line, field name (number value)
  printf '%s\n' "$1" | tail -n 1 | sed -n "s/.*\"$2\":\([0-9]*\).*/\1/p"
}

# Builds a scripts/ directory for one test workflow and prints its path.
scripts_for() { # lang, workflow file
  d=$(mktemp -d "$work/scripts.XXXXXX")
  for f in "$skill/langs/$1"/*; do
    case "$(basename "$f")" in check|GUIDE.md|ext) ;; *) cp "$f" "$d/" ;; esac
  done
  cp "$2" "$d/workflow.$(cat "$skill/langs/$1/ext")"
  echo "$d"
}

runtime_tests() { # lang
  lang=$1
  ext=$(cat "$skill/langs/$lang/ext")
  case "$lang" in ruby) comment='#' ;; *) comment='//' ;; esac

  # start creates the run; continue takes in args / answers written as files.
  begin_run() { # scripts dir, args -> sets $run
    out=$(sh "$1/run" start); run=$(field "$out" run)
    printf '%s\n' "$2" > "$run/args"
  }
  answer() { printf '%s\n' "$3" > "$1/answer.$2"; }

  # 1. ask round trip, side effects once, missing files leave the run.
  cwd=$(mktemp -d "$work/cwd.XXXXXX"); cd "$cwd" || exit 1
  d=$(scripts_for "$lang" "$here/$lang/ok.$ext")
  out=$(sh "$d/run" start); run=$(field "$out" run)
  check "$lang: start names the args file" "$run/args" "$(field "$out" write)"
  check "$lang: run directory exists" yes "$([ -d "$run" ] && echo yes)"
  sh "$d/run" continue "$run" >/dev/null 2>"$work/err"
  check "$lang: continue without args exits 2" 2 "$?"
  contains "$lang: continue without args explains" "$run/args" "$(cat "$work/err")"
  printf 'hello\n' > "$run/args"
  out=$(sh "$d/run" continue "$run")
  check "$lang: continue asks question 1" 1 "$(nfield "$out" ask)"
  check "$lang: ask 1 prompt" "first question" "$(field "$out" prompt)"
  check "$lang: ask 1 input is the arguments" "hello" "$(field "$out" input)"
  check "$lang: ask 1 names the answer file" "$run/answer.1" "$(field "$out" write)"
  check "$lang: nothing ran before ask 1" no "$([ -e counter ] && echo yes || echo no)"
  sh "$d/run" continue "$run" >/dev/null 2>"$work/err"
  check "$lang: continue without the answer exits 2" 2 "$?"
  contains "$lang: continue without the answer explains" "answer.1" "$(cat "$work/err")"
  answer "$run" 7 x
  sh "$d/run" continue "$run" >/dev/null 2>"$work/err"
  check "$lang: a wrongly numbered answer file exits 2" 2 "$?"
  check "$lang: wrong answer file keeps the run" yes "$([ -d "$run" ] && echo yes)"
  sh "$d/run" continue "$work/no-such-run" >/dev/null 2>"$work/err"
  check "$lang: unknown run exits 2" 2 "$?"
  contains "$lang: unknown run explains" "not a dullmify run" "$(cat "$work/err")"
  answer "$run" 1 one
  out=$(sh "$d/run" continue "$run")
  check "$lang: answer 1 asks question 2" 2 "$(nfield "$out" ask)"
  check "$lang: answer file is consumed" gone "$([ -e "$run/answer.1" ] || echo gone)"
  check "$lang: ask 2 input is the written file" "one" "$(field "$out" input)"
  check "$lang: command ran once" 1 "$(wc -l < counter | tr -d ' ')"
  check "$lang: write happened" "one" "$(cat out/answer.txt)"
  answer "$run" 2 two
  out=$(sh "$d/run" continue "$run")
  check "$lang: done report" "report: one|two|0|out|err|true" "$(field "$out" report)"
  check "$lang: done removes the run" gone "$([ -d "$run" ] || echo gone)"
  check "$lang: command ran once in total" 1 "$(wc -l < counter | tr -d ' ')"

  # 2. nondeterminism: finishing early leaves records unused.
  cwd=$(mktemp -d "$work/cwd.XXXXXX"); cd "$cwd" || exit 1
  d=$(scripts_for "$lang" "$here/$lang/nondet.$ext")
  begin_run "$d" early
  sh "$d/run" continue "$run" >/dev/null
  answer "$run" 1 a
  out=$(sh "$d/run" continue "$run")
  check "$lang: nondet early reaches ask B" "B" "$(field "$out" prompt)"
  : > toggle
  answer "$run" 2 b
  out=$(sh "$d/run" continue "$run")
  contains "$lang: early finish is nondeterministic" "nondeterministic" "$(field "$out" failed)"
  check "$lang: nondeterminism removes the run" gone "$([ -d "$run" ] || echo gone)"

  # 3. nondeterminism: a different question than recorded.
  cwd=$(mktemp -d "$work/cwd.XXXXXX"); cd "$cwd" || exit 1
  begin_run "$d" mismatch
  sh "$d/run" continue "$run" >/dev/null
  answer "$run" 1 a
  sh "$d/run" continue "$run" >/dev/null
  : > toggle
  answer "$run" 2 b
  out=$(sh "$d/run" continue "$run")
  contains "$lang: mismatched question is nondeterministic" "nondeterministic" "$(field "$out" failed)"

  # 4. workflow changed during the run.
  cwd=$(mktemp -d "$work/cwd.XXXXXX"); cd "$cwd" || exit 1
  d=$(scripts_for "$lang" "$here/$lang/ok.$ext")
  begin_run "$d" hello
  sh "$d/run" continue "$run" >/dev/null
  printf '%s changed\n' "$comment" >> "$d/workflow.$ext"
  answer "$run" 1 one
  out=$(sh "$d/run" continue "$run")
  contains "$lang: changed workflow fails" "workflow changed" "$(field "$out" failed)"
  check "$lang: changed workflow removes the run" gone "$([ -d "$run" ] || echo gone)"

  # 5. exceptions and fail.
  cwd=$(mktemp -d "$work/cwd.XXXXXX"); cd "$cwd" || exit 1
  case "$lang" in ruby) wf=raise.rb ;; *) wf=throw.cpp ;; esac
  d=$(scripts_for "$lang" "$here/$lang/$wf")
  begin_run "$d" ""
  sh "$d/run" continue "$run" >/dev/null
  answer "$run" 1 a
  out=$(sh "$d/run" continue "$run")
  contains "$lang: exception fails the run" "boom" "$(field "$out" failed)"
  check "$lang: exception removes the run" gone "$([ -d "$run" ] || echo gone)"
  d=$(scripts_for "$lang" "$here/$lang/fail_run.$ext")
  begin_run "$d" ""
  out=$(sh "$d/run" continue "$run")
  check "$lang: fail reports the reason" "nope" "$(field "$out" failed)"
  check "$lang: no run directory is left" "" "$(ls "$TMPDIR" | grep dullmify-run || true)"

  # 6. fail from cleanup code while a question propagates keeps the question.
  case "$lang" in ruby) wf=ensure_fail.rb ;; *) wf=dtor_fail.cpp ;; esac
  d=$(scripts_for "$lang" "$here/$lang/$wf")
  begin_run "$d" ""
  out=$(sh "$d/run" continue "$run" 2>&1)
  check "$lang: cleanup fail still asks the question" "Q" "$(field "$out" prompt)"
  check "$lang: cleanup fail keeps the run" yes "$([ -d "$run" ] && echo yes)"
  answer "$run" 1 a
  out=$(sh "$d/run" continue "$run")
  check "$lang: cleanup fail after the answer is a real failure" "cleanup saw an empty result" "$(field "$out" failed)"

  # 7. corrupt records end as failed, not as a crash.
  d=$(scripts_for "$lang" "$here/$lang/ok.$ext")
  begin_run "$d" hello
  sh "$d/run" continue "$run" >/dev/null
  printf 'garbage' > "$run/records"
  out=$(sh "$d/run" continue "$run" 2>/dev/null)
  check "$lang: corrupt records exit 0" 0 "$?"
  contains "$lang: corrupt records fail" "records" "$(field "$out" failed)"
  check "$lang: corrupt records remove the run" gone "$([ -d "$run" ] || echo gone)"

  # 8. killed after the answer was taken in: continue resumes from the records.
  d=$(scripts_for "$lang" "$here/$lang/slow.$ext")
  begin_run "$d" ""
  sh "$d/run" continue "$run" >/dev/null
  answer "$run" 1 a
  timeout 0.5 sh "$d/run" continue "$run" >/dev/null 2>&1
  check "$lang: continue was killed midway" 124 "$?"
  check "$lang: killed run keeps its directory" yes "$([ -d "$run" ] && echo yes)"
  out=$(sh "$d/run" continue "$run")
  check "$lang: continue after the kill resumes to the next question" "R" "$(field "$out" prompt)"
  check "$lang: resumed run replays the answer" "a" "$(field "$out" input)"
  answer "$run" 2 b
  out=$(sh "$d/run" continue "$run")
  check "$lang: resumed run finishes" "a|b" "$(field "$out" report)"

  # 9. usage errors.
  sh "$d/run" bogus >/dev/null 2>&1
  check "$lang: unknown command exits 2" 2 "$?"
  cd "$here" || exit 1
}

check_tests() { # lang
  lang=$1
  ext=$(cat "$skill/langs/$lang/ext")
  chk="$skill/langs/$lang/check"
  for f in "$here/$lang"/ok.$ext "$here/$lang"/ok_strings.$ext "$here/$lang"/fail_run.$ext; do
    out=$(sh "$chk" "$f" 2>&1)
    check "$lang check accepts $(basename "$f")" 0 "$?"
    [ -z "$out" ] || echo "$out" | sed 's/^/     /'
  done
  for f in "$here/$lang"/syntax_error.$ext "$here/$lang"/forbid_*.$ext; do
    sh "$chk" "$f" >/dev/null 2>&1
    check "$lang check rejects $(basename "$f")" 1 "$?"
  done
}

assemble_tests() { # lang
  lang=$1
  ext=$(cat "$skill/langs/$lang/ext")
  outdir=$(mktemp -d "$work/out.XXXXXX")
  : > "$outdir/keep.txt"
  draft() { mkdir -p "$outdir/scripts" && cp "$1" "$outdir/scripts/workflow.$ext"; }
  draft "$here/$lang/forbid_io.$ext"
  sh "$skill/assemble.sh" "$lang" "$here/fixtures/prefecture.skill.md" "$outdir" "$outdir/scripts/workflow.$ext" >/dev/null 2>&1
  check "$lang assemble rejects a bad workflow" 1 "$?"
  check "$lang assemble leaves nothing on rejection" "keep.txt" "$(ls "$outdir")"
  draft /dev/null
  sh "$skill/assemble.sh" "$lang" "$here/fixtures/prefecture.skill.md" "$outdir" "$outdir/scripts/workflow.$ext" >/dev/null 2>&1
  check "$lang assemble rejects an empty workflow" 1 "$?"
  check "$lang assemble leaves nothing after an empty workflow" "keep.txt" "$(ls "$outdir")"
  sh "$skill/assemble.sh" "$lang" "$here/fixtures/prefecture.skill.md" "$outdir" "$work/no-such-file" >/dev/null 2>&1
  check "$lang assemble rejects a missing workflow file" 1 "$?"
  draft "$here/$lang/ok.$ext"
  sh "$skill/assemble.sh" "$lang" "$here/fixtures/prefecture.skill.md" "$outdir" "$outdir/scripts/workflow.$ext" >/dev/null
  check "$lang assemble succeeds" 0 "$?"
  check "$lang assemble keeps the workflow content" "" "$(diff "$here/$lang/ok.$ext" "$outdir/scripts/workflow.$ext")"
  draft "$here/$lang/forbid_io.$ext"
  sh "$skill/assemble.sh" "$lang" "$here/fixtures/prefecture.skill.md" "$outdir" "$outdir/scripts/workflow.$ext" >/dev/null 2>&1
  check "$lang assemble regenerating in place removes scripts on rejection" "SKILL.md keep.txt" "$(ls "$outdir" | tr '\n' ' ' | sed 's/ $//')"
  draft "$here/$lang/ok.$ext"
  sh "$skill/assemble.sh" "$lang" "$here/fixtures/prefecture.skill.md" "$outdir" "$outdir/scripts/workflow.$ext" >/dev/null
  check "$lang assemble writes SKILL.md, scripts, keeps others" "SKILL.md keep.txt scripts" "$(ls "$outdir" | tr '\n' ' ' | sed 's/ $//')"
  check "$lang assemble copies run, runtime, workflow" yes "$([ -f "$outdir/scripts/run" ] && [ -f "$outdir/scripts/workflow.$ext" ] && ls "$outdir/scripts" | grep -q '^runtime\.' && echo yes)"
  awk 'f { print } /^---$/ { n++; if (n == 2) f = 1 }' "$outdir/SKILL.md" > "$work/body"
  check "$lang assemble body matches the template" "" "$(diff "$skill/templates/thin-skill.md" "$work/body")"
  check "$lang assemble allowed-tools is Write and the launcher only" 'allowed-tools: Write Bash(sh ${CLAUDE_SKILL_DIR}/scripts/run *)' "$(grep '^allowed-tools:' "$outdir/SKILL.md")"
  check "$lang assemble keeps name" "name: prefecture" "$(grep '^name:' "$outdir/SKILL.md")"
}

assemble_common_tests() {
  outdir=$(mktemp -d "$work/out.XXXXXX")
  sh "$skill/assemble.sh" nolang "$here/fixtures/prefecture.skill.md" "$outdir" "$here/ruby/ok.rb" >/dev/null 2>"$work/err"
  check "assemble rejects an unknown language" 1 "$?"
  contains "assemble lists available languages" "available: cpp ruby" "$(cat "$work/err")"
  printf -- '---\n---\nbody\n' > "$work/empty-fm.md"
  sh "$skill/assemble.sh" ruby "$work/empty-fm.md" "$outdir" "$here/ruby/ok.rb" >/dev/null 2>&1
  check "assemble rejects an empty frontmatter" 1 "$?"
}

langs=${1:-"ruby cpp"}
for lang in $langs; do
  echo "== $lang"
  runtime_tests "$lang"
  check_tests "$lang"
  assemble_tests "$lang"
done
assemble_common_tests
echo "$((total - fails)) / $total passed"
[ "$fails" -eq 0 ]
