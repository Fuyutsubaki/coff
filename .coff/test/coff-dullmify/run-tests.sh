#!/bin/sh

# 両言語の単体テスト、再実行のシナリオ、構文検査を一度に確かめる。
set -eu

test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
repo_dir=$(CDPATH= cd -- "$test_dir/../../.." && pwd -P)
source_dir=$repo_dir/.coff/src/coff-dullmify.skill
temporary=$(mktemp -d "${TMPDIR:-/tmp}/coff-dullmify-tests.XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM
mkdir -p "$temporary/tmp" "$temporary/work"

pass_count=0
pass() {
  pass_count=$((pass_count + 1))
  echo "成功: $1"
}

fail_test() {
  echo "失敗: $1" >&2
  exit 1
}

json_get() {
  ruby -rjson -e 'value = JSON.parse(STDIN.read.lines.last).fetch(ARGV.fetch(0)); puts(value)' "$1"
}

assert_json_key() {
  output=$1
  key=$2
  printf '%s\n' "$output" | json_get "$key" >/dev/null || fail_test "JSON に $key がありません"
}

make_skill() {
  language=$1
  workflow_name=$2
  destination=$(mktemp -d "$temporary/skill-$language-$workflow_name.XXXXXX")
  cp -R "$source_dir/langs/$language/." "$destination/"
  case "$language" in
    ruby) cp "$test_dir/workflows/ruby/$workflow_name.rb" "$destination/workflow.rb" ;;
    cpp) cp "$test_dir/workflows/cpp/$workflow_name.cpp" "$destination/workflow.cpp" ;;
  esac
  echo "$destination"
}

start_run() {
  skill=$1
  work=$2
  (cd "$work" && TMPDIR="$temporary/tmp" sh "$skill/run" start)
}

continue_run() {
  skill=$1
  run=$2
  TMPDIR="$temporary/tmp" sh "$skill/run" continue "$run"
}

test_ok() {
  language=$1
  skill=$(make_skill "$language" ok)
  work=$temporary/work/ok-$language
  mkdir -p "$work"
  started=$(start_run "$skill" "$work")
  run=$(printf '%s\n' "$started" | json_get run)
  repeated=$(continue_run "$skill" "$run")
  [ "$started" = "$repeated" ] || fail_test "$language: args 未作成時の出力が変わりました"
  [ ! -e "$run/records.jsonl" ] || fail_test "$language: args 未作成時に記録ができました"

  printf '%s\n' "引数" > "$run/args"
  first=$(continue_run "$skill" "$run")
  assert_json_key "$first" prompt
  before=$(cksum "$run/records.jsonl")
  same=$(continue_run "$skill" "$run")
  after=$(cksum "$run/records.jsonl")
  [ "$first" = "$same" ] || fail_test "$language: answer 未作成時の問いが変わりました"
  [ "$before" = "$after" ] || fail_test "$language: answer 未作成時に記録が変わりました"

  printf '%s\n' "甲" > "$run/answer"
  second=$(continue_run "$skill" "$run")
  assert_json_key "$second" prompt
  [ ! -e "$run/answer" ] || fail_test "$language: 取り込んだ answer が残っています"
  printf '%s\n' "乙" > "$run/answer"
  done_output=$(continue_run "$skill" "$run")
  report=$(printf '%s\n' "$done_output" | json_get report)
  [ "$report" = "引数|甲|乙" ] || fail_test "$language: report が違います: $report"
  [ ! -e "$run" ] || fail_test "$language: done 後に run が残っています"
  [ "$(wc -l < "$work/effect.log")" -eq 1 ] || fail_test "$language: effect が複数回動きました"
  pass "$language の問い、再実行、副作用の一度性"
}

test_bad_marker() {
  language=$1
  skill=$(make_skill "$language" ok)
  fake=$temporary/fake-$language
  mkdir -p "$fake"
  set +e
  TMPDIR="$temporary/tmp" sh "$skill/run" continue "$fake" >/dev/null 2>"$temporary/marker-$language.err"
  status=$?
  set -e
  [ "$status" -eq 2 ] || fail_test "$language: 目印なし run の終了コードが $status です"
  pass "$language の run 目印"
}

test_changed() {
  language=$1
  skill=$(make_skill "$language" ok)
  work=$temporary/work/change-$language
  mkdir -p "$work"
  started=$(start_run "$skill" "$work")
  run=$(printf '%s\n' "$started" | json_get run)
  printf '%s\n' "引数" > "$run/args"
  continue_run "$skill" "$run" >/dev/null
  case "$language" in
    ruby) printf '\n# テスト中の変更\n' >> "$skill/workflow.rb" ;;
    cpp) printf '\n// テスト中の変更\n' >> "$skill/workflow.cpp" ;;
  esac
  output=$(continue_run "$skill" "$run")
  assert_json_key "$output" failed
  [ ! -e "$run" ] || fail_test "$language: workflow 変更後に run が残っています"
  pass "$language の workflow 変更検出"
}

test_failure_case() {
  language=$1
  workflow_name=$2
  skill=$(make_skill "$language" "$workflow_name")
  work=$temporary/work/$workflow_name-$language
  mkdir -p "$work"
  started=$(start_run "$skill" "$work")
  run=$(printf '%s\n' "$started" | json_get run)
  printf '%s\n' "引数" > "$run/args"
  if [ "$workflow_name" = nondet ]; then
    continue_run "$skill" "$run" >/dev/null
  fi
  output=$(continue_run "$skill" "$run")
  assert_json_key "$output" failed
  [ ! -e "$run" ] || fail_test "$language: $workflow_name の失敗後に run が残っています"
  pass "$language の $workflow_name 検出"
}

test_strict() {
  language=$1
  skill=$(make_skill "$language" strict)
  work=$temporary/work/strict-$language
  mkdir -p "$work"
  started=$(start_run "$skill" "$work")
  run=$(printf '%s\n' "$started" | json_get run)
  printf '%s\n' "引数" > "$run/args"
  continue_run "$skill" "$run" >/dev/null
  printf '%s\n' "了承" > "$run/answer"
  output=$(continue_run "$skill" "$run")
  assert_json_key "$output" failed
  [ ! -e "$run" ] || fail_test "$language: done 前の非決定後に run が残っています"
  pass "$language の done 前確認"
}

test_slow_effect() {
  language=$1
  skill=$(make_skill "$language" slow)
  work=$temporary/work/slow-$language
  mkdir -p "$work"
  if [ "$language" = cpp ]; then
    warm_started=$(start_run "$skill" "$work")
    warm_run=$(printf '%s\n' "$warm_started" | json_get run)
    printf '%s\n' "ビルド" > "$warm_run/args"
    continue_run "$skill" "$warm_run" >/dev/null
  fi
  started=$(start_run "$skill" "$work")
  run=$(printf '%s\n' "$started" | json_get run)
  printf '%s\n' "引数" > "$run/args"
  set +e
  TMPDIR="$temporary/tmp" timeout 1 sh "$skill/run" continue "$run" >"$temporary/slow-$language.out" 2>"$temporary/slow-$language.err"
  status=$?
  set -e
  [ "$status" -eq 124 ] || fail_test "$language: effect の中断が timeout になりませんでした: $status"
  output=$(continue_run "$skill" "$run")
  assert_json_key "$output" failed
  [ ! -e "$run" ] || fail_test "$language: 中断 effect の検出後に run が残っています"
  pass "$language の effect 中断"
}

test_resume() {
  language=$1
  skill=$(make_skill "$language" resume)
  work=$temporary/work/resume-$language
  mkdir -p "$work"
  started=$(start_run "$skill" "$work")
  run=$(printf '%s\n' "$started" | json_get run)
  printf '%s\n' "引数" > "$run/args"
  continue_run "$skill" "$run" >/dev/null
  printf '%s\n' "甲" > "$run/answer"
  set +e
  TMPDIR="$temporary/tmp" timeout 1 sh "$skill/run" continue "$run" >"$temporary/resume-$language.out" 2>"$temporary/resume-$language.err"
  status=$?
  set -e
  [ "$status" -eq 124 ] || fail_test "$language: 問い後の中断が timeout になりませんでした: $status"
  next=$(continue_run "$skill" "$run")
  assert_json_key "$next" prompt
  [ "$(printf '%s\n' "$next" | json_get input)" = "甲" ] || fail_test "$language: 回答記録後に続きへ進めません"
  printf '%s\n' "乙" > "$run/answer"
  done_output=$(continue_run "$skill" "$run")
  [ "$(printf '%s\n' "$done_output" | json_get report)" = "甲|乙" ] || fail_test "$language: 再開後の report が違います"
  pass "$language の回答記録後の再開"
}

test_invalid_utf8() {
  language=$1
  skill=$(make_skill "$language" invalid_utf8)
  work=$temporary/work/utf8-$language
  mkdir -p "$work"
  started=$(start_run "$skill" "$work")
  run=$(printf '%s\n' "$started" | json_get run)
  printf '%s\n' "引数" > "$run/args"
  output=$(continue_run "$skill" "$run")
  [ "$(printf '%s\n' "$output" | json_get report)" = "a�b" ] || fail_test "$language: 不正 UTF-8 を置換できません"
  pass "$language の不正 UTF-8"
}

test_syntax() {
  language=$1
  case "$language" in
    ruby) good=$test_dir/workflows/ruby/ok.rb; bad=$test_dir/workflows/ruby/syntax_error.rb ;;
    cpp) good=$test_dir/workflows/cpp/ok.cpp; bad=$test_dir/workflows/cpp/syntax_error.cpp ;;
  esac
  sh "$source_dir/langs/$language/check" "$good" >/dev/null
  if sh "$source_dir/langs/$language/check" "$bad" >"$temporary/syntax-$language.out" 2>"$temporary/syntax-$language.err"; then
    fail_test "$language: 構文エラーを受理しました"
  fi
  pass "$language の構文検査"
}

echo "Ruby 単体テスト"
MT_NO_PLUGINS=1 ruby "$test_dir/unit/ruby/runtime_test.rb"
pass "Ruby ランタイム単体テスト"

echo "C++ 単体テスト"
"${CXX:-c++}" -std=c++17 -I"$source_dir/langs/cpp" -I"$test_dir/unit/cpp" \
  "$test_dir/unit/cpp/runtime_test.cpp" -o "$temporary/cpp-unit"
"$temporary/cpp-unit"
pass "C++ ランタイム単体テスト"

for language in ruby cpp; do
  test_ok "$language"
  test_bad_marker "$language"
  test_changed "$language"
  test_failure_case "$language" nondet
  if [ "$language" = ruby ]; then
    test_failure_case "$language" raise
  else
    test_failure_case "$language" throw
  fi
  test_strict "$language"
  test_slow_effect "$language"
  test_resume "$language"
  test_invalid_utf8 "$language"
  test_syntax "$language"
done

echo "全 $pass_count 項目に成功しました"
