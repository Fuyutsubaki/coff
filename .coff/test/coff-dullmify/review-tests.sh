#!/bin/sh

# 独立した Claude に同じ点検雛形を渡し、good と単一欠陥の判定を確かめる。
set -eu

test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
repo_dir=$(CDPATH= cd -- "$test_dir/../../.." && pwd -P)
skill_dir=$repo_dir/.coff/src/coff-dullmify.skill
source_file=$test_dir/fixtures/prefecture.skill.md
temporary=$(mktemp -d "${TMPDIR:-/tmp}/coff-dullmify-review.XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM

build_prompt() {
  workflow=$1
  guide=$2
  destination=$3
  ruby -e '
    template, source, workflow, guide, destination = ARGV
    text = File.read(template, encoding: "UTF-8")
    body = text[/```text\n(.*?)\n```/m, 1] or abort "点検雛形を読めません"
    body = body.sub("{{SOURCE}}", File.read(source, encoding: "UTF-8"))
               .sub("{{WORKFLOW}}", File.read(workflow, encoding: "UTF-8"))
               .sub("{{GUIDE}}", File.read(guide, encoding: "UTF-8"))
    File.write(destination, body)
  ' "$skill_dir/review.md" "$source_file" "$workflow" "$guide" "$destination"
}

check_one() {
  language=$1
  name=$2
  expected=$3
  case "$language" in
    ruby) suffix=rb ;;
    cpp) suffix=cpp ;;
  esac
  workflow=$test_dir/review/$language/$name.$suffix
  prompt=$temporary/prompt-$language-$name.txt
  build_prompt "$workflow" "$skill_dir/langs/$language/GUIDE.md" "$prompt"
  response=$(claude -p "$(cat "$prompt")")
  first=$(printf '%s\n' "$response" | sed -n '1p' | tr -d '\r')
  if [ "$first" != "$expected" ]; then
    echo "失敗: $language/$name は $expected のはずですが、先頭行は $first でした" >&2
    printf '%s\n' "$response" >&2
    exit 1
  fi
  echo "成功: $language/$name = $expected"
}

for language in ruby cpp; do
  for name in bad_stdout bad_file bad_time bad_once_write bad_rescue bad_missing bad_branch; do
    check_one "$language" "$name" 不合格
  done
  check_one "$language" good 合格
done

echo "点検の全題材に成功しました"
