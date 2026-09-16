---
name: coff-init
description: coff のスキル一式を導入先 repo にセットアップする。不足している coff スキルの一括導入と、issue 運用の初期化（`issue/` 作成、規約ファイルへの規約追記）を行う。
license: MIT
coff-dist: true
---

<!--
導入の入口 skill。gh skill install は 1 コマンド 1 スキルしか受け付けないため、最初に本 skill だけを入れ、残りはここから一括導入する（issue/2026/07/1921-gh-skill-installable.md の判断）。agent ごとの配置と規約ファイルの違いは、自身の配置場所から判別して吸収する（issue/2026/09/1515-drop-claude-dependency.md の判断）。
-->

## 手順

1. 前提確認: カレントディレクトリが git リポジトリであること、`gh` CLI が使えること、`gh skill --help` が成功すること（agent skills 対応版であること）を確認する。欠けていれば、何が足りないかを報告して中断する。
2. agent の判別: この SKILL.md の配置パス（agent が skill の読み込み時に提示する）で判別する。`.claude/skills/` 配下なら claude-code、`.agents/skills/` 配下なら codex。判別できなければユーザーに聞く。以降、`<agent>` は判別した値、`<dir>` はその配置ディレクトリ（`.claude/skills/` または `.agents/skills/`）、`<rules>` は agent の規約ファイル（claude-code は CLAUDE.md、codex は AGENTS.md）を指す。 <!-- 環境変数で判別しないのは、codex にセッションを識別する安定した変数が無いため -->
3. 兄弟スキルの導入: `<dir>` にディレクトリが存在しない coff スキルを、次のコマンドで 1 つずつ導入する。不足判定はディレクトリの有無だけで行い、版の新旧は見ない。

   ```bash
   # 対象: coff-detail-issue coff-issue-create coff-issue-polish coff-issue-done
   #       coff-issue-list coff-compile coff-japanese-tech-writing
   #       coff-argument-gap-edit coff-review-diff-code
   gh skill install Fuyutsubaki/coff <name> --agent <agent>
   ```

   `--agent <agent>` は省略しない。 <!-- 省くと非対話時の既定が github-copilot になり、別のディレクトリに入る --> ネットワークと `<dir>` への書き込みが要る（codex のサンドボックスは `.agents/` を読み取り専用にする）。
4. 初期化:
   - `issue/` ディレクトリがなければ作成する。
   - `<rules>` に coff の規約節を追記する。ファイルがなければ作成する。既に見出し `## coff` があれば何もしない。 <!-- 再実行しても重複させない -->既存の記述には触れず、末尾に次の節を追加する。`<dir>` は判別した配置ディレクトリに置き換える。

     ```markdown
     ## coff
     - `<dir>` 配下の coff 成果物（skills など）は手で編集しない。変更は `.coff/src/` のソースを編集し、coff-compile skill でビルドする。
     - issue 運用の入口は coff-issue-create skill。流れは create → polish → 実装 → done。一覧は coff-issue-list skill。
     ```
5. 報告: 判別した agent、導入したスキル、初期化の結果を報告する。あわせて issue 運用の流れ（create → polish → 実装 → done）と、自作スキルをソース管理するなら `.coff/src/` 規約と coff-compile skill が使えることを短く案内する。

## 出口基準

- coff スキル一式が `<dir>` に揃い、`issue/` と `<rules>` の coff 節が存在すること。
