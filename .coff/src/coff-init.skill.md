---
name: coff-init
description: coff のスキル一式を導入先 repo にセットアップする。不足している coff スキルの一括導入と、issue 運用の初期化（`issue/` 作成、CLAUDE.md への規約追記）を行う。
license: MIT
coff-dist: true
---

<!--
導入の入口 skill。gh skill install は 1 コマンド 1 スキルしか受け付けないため、最初に本 skill だけを入れ、残りはここから一括導入する（issue/2026/07/1921-gh-skill-installable.md の判断）。
-->

## 手順

1. 前提確認: カレントディレクトリが git リポジトリであること、`gh` CLI が使えること、`gh skill --help` が成功すること（agent skills 対応版であること）を確認する。欠けていれば、何が足りないかを報告して中断する。
2. 兄弟スキルの導入: `.claude/skills/` にディレクトリが存在しない coff スキルを、次のコマンドで 1 つずつ導入する。不足判定はディレクトリの有無だけで行い、版の新旧は見ない。

   ```bash
   # 対象: coff-detail-issue coff-issue-create coff-issue-polish coff-issue-done
   #       coff-compile coff-japanese-tech-writing coff-argument-gap-edit
   gh skill install Fuyutsubaki/coff <name> --agent claude-code
   ```

   `--agent claude-code` は省略しない。 <!-- 省くと非対話時の既定が github-copilot になり、.claude/skills/ に入らない -->
3. 初期化:
   - `issue/` ディレクトリがなければ作成する。
   - CLAUDE.md に coff の規約節を追記する。ファイルがなければ作成する。既に見出し `## coff` があれば何もしない。 <!-- 再実行しても重複させない -->既存の記述には触れず、末尾に次の節をそのまま追加する:

     ```markdown
     ## coff
     - `.claude/` 配下の coff 成果物（skills など）は手で編集しない。変更は `.coff/src/` のソースを編集し、`/coff-compile` でビルドする。
     - issue 運用の入口は coff-issue-create skill。流れは create → polish → 実装 → done。
     ```
4. 報告: 導入したスキルと初期化の結果を報告する。あわせて issue 運用の流れ（create → polish → 実装 → done）と、自作スキルをソース管理するなら `.coff/src/` 規約と `/coff-compile` が使えることを短く案内する。

## 出口基準

- coff スキル一式が `.claude/skills/` に揃い、`issue/` と CLAUDE.md の coff 節が存在すること。
