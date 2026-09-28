#!/bin/sh

# 両言語の単体テスト、構文検査、再実行の実動作をまとめて確認する。
set -u

test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 2
repo_dir=$(CDPATH= cd -- "$test_dir/../../.." && pwd -P) || exit 2
source_dir=$repo_dir/.coff/src/coff-dullmify.skill
temporary=$(mktemp -d "${TMPDIR:-/tmp}/coff-dullmify-test.XXXXXX") || exit 2
trap 'rm -rf "$temporary"' EXIT HUP INT TERM
# run とビルドキャッシュもテスト用の一時ディレクトリの中に作らせる。
TMPDIR=$temporary/tmp
export TMPDIR
mkdir -p "$TMPDIR" || exit 2

failures=0

pass() {
  echo "成功: $1"
}

fail() {
  echo "失敗: $1" >&2
  failures=$((failures + 1))
}

json_value() {
  ruby -rjson -e 'value = JSON.parse(STDIN.read); result = value.fetch(ARGV[0]); print(result.is_a?(String) ? result : JSON.generate(result))' "$1"
}

has_json_key() {
  ruby -rjson -e 'exit(JSON.parse(STDIN.read).key?(ARGV[0]) ? 0 : 1)' "$1"
}

prepare_case() {
  language=$1
  name=$2
  case_dir=$temporary/cases/$language-$name
  mkdir -p "$case_dir" || exit 2
  cp -R "$source_dir/langs/$language" "$case_dir/scripts" || exit 2
  case $language in
    ruby) cp "$test_dir/workflows/ruby/$name.rb" "$case_dir/scripts/workflow.rb" || exit 2 ;;
    cpp) cp "$test_dir/workflows/cpp/$name.cpp" "$case_dir/scripts/workflow.cpp" || exit 2 ;;
  esac
  printf '%s' "$case_dir"
}

start_case() {
  case_dir=$1
  (cd "$case_dir" && sh "$case_dir/scripts/run" start)
}

continue_case() {
  case_dir=$1
  run_dir=$2
  (cd "$case_dir" && sh "$case_dir/scripts/run" continue "$run_dir")
}

test_standard_run() {
  language=$1
  case_dir=$(prepare_case "$language" ok)
  start_output=$(start_case "$case_dir") || {
    fail "$language: start"
    return
  }
  run_dir=$(printf '%s' "$start_output" | json_value run) || {
    fail "$language: start の JSON"
    return
  }

  before=$(find "$run_dir" -maxdepth 1 -type f -print | sort | cksum)
  missing_output=$(continue_case "$case_dir" "$run_dir")
  after=$(find "$run_dir" -maxdepth 1 -type f -print | sort | cksum)
  if [ "$missing_output" = "$start_output" ] && [ "$before" = "$after" ]; then
    pass "$language: args 未作成なら同じ出力で記録を変えない"
  else
    fail "$language: args 未作成時の再提示"
  fi

  printf 'テスト入力\n' >"$run_dir/args"
  first=$(continue_case "$case_dir" "$run_dir")
  first_prompt=$(printf '%s' "$first" | json_value prompt 2>/dev/null || true)
  records_before=$(cksum "$run_dir/records.jsonl")
  repeated=$(continue_case "$case_dir" "$run_dir")
  records_after=$(cksum "$run_dir/records.jsonl")
  if [ "$first" = "$repeated" ] && [ "$records_before" = "$records_after" ] && [ "$first_prompt" = "最初の値を答えてください" ]; then
    pass "$language: 未回答の問いを同じ記録で再提示"
  else
    fail "$language: 未回答の問いの再提示"
  fi

  printf '甲\n' >"$run_dir/answer"
  second=$(continue_case "$case_dir" "$run_dir")
  second_prompt=$(printf '%s' "$second" | json_value prompt 2>/dev/null || true)
  printf '乙\n' >"$run_dir/answer"
  done_output=$(continue_case "$case_dir" "$run_dir")
  report=$(printf '%s' "$done_output" | json_value report 2>/dev/null || true)
  side_effect_count=$(wc -l <"$case_dir/side-effect.log" 2>/dev/null || printf 0)
  if [ "$second_prompt" = "二つ目の値を答えてください" ] && [ "$report" = "完了: 甲/乙" ] && [ "$side_effect_count" -eq 1 ] && [ ! -e "$run_dir" ]; then
    pass "$language: 問いの往復、副作用一回、完了時の片付け"
  else
    fail "$language: 標準の完走（出力: $done_output）"
  fi
}

test_nondeterminism() {
  language=$1
  case_dir=$(prepare_case "$language" nondet)
  start_output=$(start_case "$case_dir") || { fail "$language: 非決定 start"; return; }
  run_dir=$(printf '%s' "$start_output" | json_value run)
  printf '入力' >"$run_dir/args"
  continue_case "$case_dir" "$run_dir" >/dev/null
  output=$(continue_case "$case_dir" "$run_dir")
  if printf '%s' "$output" | has_json_key failed && [ ! -e "$run_dir" ]; then
    pass "$language: 再実行の食い違いを failed にする"
  else
    fail "$language: 非決定の検出（出力: $output）"
  fi
}

test_workflow_change() {
  language=$1
  case_dir=$(prepare_case "$language" ok)
  start_output=$(start_case "$case_dir") || { fail "$language: 変更検出 start"; return; }
  run_dir=$(printf '%s' "$start_output" | json_value run)
  printf '入力' >"$run_dir/args"
  continue_case "$case_dir" "$run_dir" >/dev/null
  case $language in
    ruby) printf '\n# テスト中の変更\n' >>"$case_dir/scripts/workflow.rb" ;;
    cpp) printf '\n// テスト中の変更\n' >>"$case_dir/scripts/workflow.cpp" ;;
  esac
  output=$(continue_case "$case_dir" "$run_dir")
  if printf '%s' "$output" | has_json_key failed && [ ! -e "$run_dir" ]; then
    pass "$language: workflow の途中変更を検出"
  else
    fail "$language: workflow の変更検出（出力: $output）"
  fi
}

test_exception() {
  language=$1
  workflow_name=raise
  [ "$language" = cpp ] && workflow_name=throw
  case_dir=$(prepare_case "$language" "$workflow_name")
  start_output=$(start_case "$case_dir") || { fail "$language: 例外 start"; return; }
  run_dir=$(printf '%s' "$start_output" | json_value run)
  printf '入力' >"$run_dir/args"
  output=$(continue_case "$case_dir" "$run_dir")
  if printf '%s' "$output" | has_json_key failed && [ ! -e "$run_dir" ]; then
    pass "$language: 例外を failed にして片付ける"
  else
    fail "$language: 例外処理（出力: $output）"
  fi
}

test_invalid_utf8() {
  language=$1
  case_dir=$(prepare_case "$language" invalid_utf8)
  start_output=$(start_case "$case_dir") || { fail "$language: UTF-8 start"; return; }
  run_dir=$(printf '%s' "$start_output" | json_value run)
  printf '入力' >"$run_dir/args"
  output=$(continue_case "$case_dir" "$run_dir")
  if printf '%s' "$output" | ruby -rjson -e 'value = JSON.parse(STDIN.read); exit(value["done"] && value["report"].include?("�") ? 0 : 1)'; then
    pass "$language: 不正な UTF-8 を置換した JSON"
  else
    fail "$language: 不正な UTF-8 の JSON（出力: $output）"
  fi
}

test_killed_resume() {
  language=$1
  case_dir=$(prepare_case "$language" slow)
  start_output=$(start_case "$case_dir") || { fail "$language: 再開 start"; return; }
  run_dir=$(printf '%s' "$start_output" | json_value run)
  printf '入力' >"$run_dir/args"
  continue_case "$case_dir" "$run_dir" >/dev/null
  printf '一つ目の回答\n' >"$run_dir/answer"
  timeout 0.5 sh -c 'cd "$1" && sh "$1/scripts/run" continue "$2"' _ "$case_dir" "$run_dir" >/dev/null 2>&1 || true
  if [ ! -e "$run_dir/answer" ] && [ -e "$run_dir" ]; then
    output=$(continue_case "$case_dir" "$run_dir")
    prompt=$(printf '%s' "$output" | json_value prompt 2>/dev/null || true)
    if [ "$prompt" = "再開後の問い" ]; then
      pass "$language: 強制終了後に記録済みの回答から再開"
      find "$run_dir" -depth -delete
      return
    fi
  fi
  fail "$language: 強制終了後の再開"
}

test_syntax() {
  language=$1
  case $language in
    ruby) extension=rb ;;
    cpp) extension=cpp ;;
  esac
  if sh "$source_dir/langs/$language/check" "$test_dir/workflows/$language/ok.$extension" >/dev/null 2>&1 &&
     ! sh "$source_dir/langs/$language/check" "$test_dir/workflows/$language/syntax_error.$extension" >/dev/null 2>&1; then
    pass "$language: 構文検査"
  else
    fail "$language: 構文検査"
  fi
}

test_marker() {
  language=$1
  case_dir=$(prepare_case "$language" ok)
  fake=$temporary/fake-$language
  mkdir -p "$fake"
  if (cd "$case_dir" && sh "$case_dir/scripts/run" continue "$fake" >/dev/null 2>"$temporary/marker-$language.err"); then
    fail "$language: 目印のない run を受理した"
  else
    code=$?
    if [ "$code" -eq 2 ]; then pass "$language: 目印のない run は終了コード 2"; else fail "$language: 目印のない run の終了コード $code"; fi
  fi
}

echo "Ruby 単体テスト"
if MT_NO_PLUGINS=1 ruby "$test_dir/unit/ruby/runtime_test.rb"; then pass "Ruby 単体テスト"; else fail "Ruby 単体テスト"; fi

echo "C++ 単体テスト"
# doctest は unit/cpp/ に同梱した単一ヘッダを使う。
if ${CXX:-c++} -std=c++17 -I"$source_dir/langs/cpp" -I"$test_dir/unit/cpp" "$test_dir/unit/cpp/runtime_test.cpp" -o "$temporary/cpp-unit" && "$temporary/cpp-unit"; then
  pass "C++ 単体テスト"
else
  fail "C++ 単体テスト"
fi

for language in ruby cpp; do
  test_syntax "$language"
  test_standard_run "$language"
  test_nondeterminism "$language"
  test_workflow_change "$language"
  test_exception "$language"
  test_invalid_utf8 "$language"
  test_killed_resume "$language"
  test_marker "$language"
done

build_base=$temporary/build-failure
mkdir -p "$build_base"
case_dir=$(prepare_case cpp ok)
build_run=$(cd "$case_dir" && TMPDIR="$build_base" sh "$case_dir/scripts/run" start | json_value run)
: >"$build_run/args"
build_output=$(cd "$case_dir" && TMPDIR="$build_base" CXX=false sh "$case_dir/scripts/run" continue "$build_run" 2>/dev/null)
if printf '%s' "$build_output" | has_json_key failed && [ ! -e "$build_run" ]; then
  pass "C++: ビルド失敗を固定の failed JSON にして run を消す"
else
  fail "C++: ビルド失敗の出力（$build_output）"
fi
marker_output=$(cd "$case_dir" && TMPDIR="$build_base" CXX=false sh "$case_dir/scripts/run" continue "$build_base" 2>/dev/null)
if [ "$?" -eq 2 ] && [ -z "$marker_output" ]; then
  pass "C++: 目印のない run はビルドより先に終了コード 2"
else
  fail "C++: 目印のない run の出力（$marker_output）"
fi

if [ "$failures" -eq 0 ]; then
  echo "すべてのテストに成功しました"
  exit 0
fi

echo "$failures 件のテストが失敗しました" >&2
exit 1
