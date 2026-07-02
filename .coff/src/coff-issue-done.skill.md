---
name: coff-issue-done
description: `issue/` の issue を完了扱いにする。frontmatter の `status` を `done` に更新する。
---

<!--
完了マークを付ける専用 skill。frontmatter の status を done にするだけ。本文は変えない。状態の共通仕様は coff-detail-issue を唯一の参照元とする。
-->

## 手順

1. `.claude/skills/coff-detail-issue/SKILL.md` の状態仕様を把握する。 <!-- skill は自動では相互ロードされないので明示的に読む -->
2. 引数で渡された対象 issue ファイルを読む。
3. frontmatter と `status` の有無で分岐して `done` にする。
   - frontmatter があり `status` があれば、その値を `done` に書き換える。
   - frontmatter はあるが `status` が無ければ、`status: done` を frontmatter に追加する。
   - frontmatter が無ければ、ファイル先頭に `---` / `status: done` / `---` を挿入する（本文はそのまま後続させる）。
4. 本文（`#` 以降）は一切変更しない。
5. 更新後のパスと新しい `status` を報告する。

## 適用範囲

- 更新は `done` 方向のみ。取り消し（`done` → `open`）は手編集で行う。
