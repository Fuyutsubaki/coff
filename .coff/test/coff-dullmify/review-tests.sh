#!/bin/sh

# review.md の雛形を使い、意図した合否を独立した Claude に判定させる。
set -u

test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 2
repo_dir=$(CDPATH= cd -- "$test_dir/../../.." && pwd -P) || exit 2
skill_dir=$repo_dir/.coff/src/coff-dullmify.skill
temporary=$(mktemp -d "${TMPDIR:-/tmp}/coff-dullmify-review.XXXXXX") || exit 2
trap 'find "$temporary" -depth -delete 2>/dev/null || true' EXIT HUP INT TERM

if ! command -v claude >/dev/null 2>&1; then
  echo "claude コマンドがないため点検テストを実行できません" >&2
  exit 2
fi

failures=0
review_timeout=${DULLMIFY_REVIEW_TIMEOUT:-120}

make_prompt() {
  workflow=$1
  guide=$2
  output=$3
  ruby -e '
    template = File.read(ARGV[0], encoding: "UTF-8")
    source = File.read(ARGV[1], encoding: "UTF-8")
    workflow = File.read(ARGV[2], encoding: "UTF-8")
    guide = File.read(ARGV[3], encoding: "UTF-8")
    prompt = template.sub(/.*?## プロンプト雛形\n\n/m, "")
    prompt = prompt.sub("{{SOURCE}}") { source }.sub("{{WORKFLOW}}") { workflow }.sub("{{GUIDE}}") { guide }
    File.binwrite(ARGV[4], prompt)
  ' "$skill_dir/review.md" "$test_dir/fixtures/prefecture.skill.md" "$workflow" "$guide" "$output"
}

run_review() {
  language=$1
  name=$2
  expected=$3
  case $language in
    ruby) extension=rb ;;
    cpp) extension=cpp ;;
  esac
  workflow=$test_dir/review/$language/$name.$extension
  prompt=$temporary/$language-$name.prompt
  make_prompt "$workflow" "$skill_dir/langs/$language/GUIDE.md" "$prompt" || {
    echo "失敗: $language/$name のプロンプトを作れません" >&2
    failures=$((failures + 1))
    return
  }
  output=$(timeout "$review_timeout" claude -p <"$prompt")
  status=$?
  first=$(printf '%s\n' "$output" | sed -n '1{s/\r$//;p;}')
  if [ "$status" -eq 0 ] && [ "$first" = "$expected" ]; then
    echo "成功: $language/$name は $expected"
  else
    echo "失敗: $language/$name は $expected の予定（終了コード $status）" >&2
    if [ "$status" -eq 124 ]; then
      echo "claude -p が ${review_timeout} 秒以内に応答しませんでした" >&2
    fi
    printf '%s\n' "$output" >&2
    failures=$((failures + 1))
  fi
}

for language in ruby cpp; do
  run_review "$language" bad_stdout 不合格
  run_review "$language" bad_file 不合格
  run_review "$language" bad_rescue 不合格
  run_review "$language" bad_missing 不合格
  run_review "$language" bad_branch 不合格
  run_review "$language" good 合格
done

if [ "$failures" -eq 0 ]; then
  echo "すべての点検テストに成功しました"
  exit 0
fi

echo "$failures 件の点検テストが失敗しました" >&2
exit 1
