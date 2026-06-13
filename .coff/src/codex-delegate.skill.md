---
name: codex-delegate
description: 独立した実装・調査・バグ修正タスクを codex@openai-codex プラグインに委譲する。
---

<!--
委譲ロジックの単一ソース。判断・調査・手順をここに置く。codex の隔離実行（別プロセス・別サブエージェント）は /codex:rescue が内蔵しているので、独自のサブエージェントは持たない。
-->

## いつ委譲するか

- 自己完結した実装/調査/バグ修正（メイン context を使わず別プロセスで回したい）
- 委譲しない: 小さな編集、ユーザーと密に往復が要る作業

## 手順

1. ブリーフを作る: 目的 / 制約 / 対象ファイル / 完了条件。
   - codex は別プロセスで自分でも探索するので、軽いブリーフで足りるならそれでよい。
   - repo 固有の前提や勘所を渡したいときは、関連ファイル/構造/依存をこの段で調査してブリーフに織り込む。
2. 短いタスク → `/codex:rescue <brief>`（同期）。長い/並行 → `/codex:rescue --background <brief>`。
3. 進捗: `/codex:status`。
4. 回収: `/codex:result <task-id>` → レビューして統合。
5. 続行/中断: `--resume <task-id>` / `/codex:cancel`。

## 注意

- 初回のみ `/codex:setup` で codex の認証を確認する。
