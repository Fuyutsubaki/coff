---
name: coff-repo-init
description: 導入先 repo で coff の issue 運用を初期化する（`issue/` 作成、CLAUDE.md への規約追記）。スキルの導入は行わない。coff スキルをユーザースコープ（`~/.claude/skills/`）に入れているときの入口。
license: MIT
coff-dist: true
---

<!--
coff-init の repo 側の工程だけを切り出した skill。coff スキルをユーザースコープに入れていると、coff-init は導入先 repo の `.claude/skills/` に重複コピーを作ってしまうため、スキル導入を含まないこの skill を入口にする。CLAUDE.md に追記する節は coff-init と同じ文言にし、どちらで初期化しても同じ結果になるようにする。
-->

## 手順

1. 前提確認: カレントディレクトリが git リポジトリであることを確認する。違えば報告して中断する。
2. 初期化:
   - `issue/` ディレクトリがなければ作成する。
   - CLAUDE.md に coff の規約節を追記する。ファイルがなければ作成する。既に見出し `## coff` があれば何もしない。 <!-- 再実行しても重複させない -->既存の記述には触れず、末尾に次の節をそのまま追加する:

     ```markdown
     ## coff
     - `.claude/` 配下の coff 成果物（skills など）は手で編集しない。変更は `.coff/src/` のソースを編集し、`/coff-compile` でビルドする。
     - issue 運用の入口は coff-issue-create skill。流れは create → polish → 実装 → done。一覧は coff-issue-list skill。
     ```
3. 報告: 初期化の結果を報告する。あわせて issue 運用の流れ（create → polish → 実装 → done）を短く案内する。

## 出口基準

- `issue/` と CLAUDE.md の coff 節が存在すること。
