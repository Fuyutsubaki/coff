---
name: compile
description: coff repo のビルド入口。`/coff-compile` のラッパーで、`coff-dist` を宣言したスキルの配布ミラー `skills/` の同期まで行う。引数はそのまま渡す。
---

<!-- coff-compile は他 repo にも配る汎用ツールなので、coff repo 固有のポリシー（何をどこへ配布するか）は compile 本体でなくこのラッパーに置く。issue/2026/07/1921-gh-skill-installable.md の判断 -->

## 手順

1. 受け取った引数をそのまま渡して `/coff-compile`（`.claude/skills/coff-compile/SKILL.md`）を実行する。
2. ミラー同期。引数に `--lint-only` があればこの手順は行わない。ソース frontmatter に `coff-dist: true` を持つ skill 型それぞれについて、配布ミラー `skills/<name>/SKILL.md` を正本 `.claude/skills/<name>/SKILL.md` の複製として同期する。

   ```bash
   for src in .coff/src/*.skill.md; do
     sed -n '2,/^---$/p' "$src" | grep -q '^coff-dist:[[:space:]]*true' || continue
     name=$(basename "$src" .skill.md)
     mkdir -p "skills/$name"
     cmp -s ".claude/skills/$name/SKILL.md" "skills/$name/SKILL.md" \
       || { cp ".claude/skills/$name/SKILL.md" "skills/$name/SKILL.md"; echo "mirrored: $name"; }
   done
   ```

3. 同期の出力（`mirrored: <name>`）があれば coff-compile の報告に足す。

## ルール

- `coff-dist` は coff repo の配布宣言で、解釈するのはこのラッパーだけ。 <!-- 配布ミラーは gh skill の発見規約 skills/*/SKILL.md に合わせた実体の複製。install はこのディレクトリだけを導入先へコピーするので、参照 stub にはできない -->
- 宣言を外したソースのミラー削除は手動で行う。
