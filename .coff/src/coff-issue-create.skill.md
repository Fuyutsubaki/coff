---
name: coff-issue-create
description: 新しい issue を `issue/` 配下に雛形生成する。
---

<!--
雛形生成のみを担う軽い skill。磨き込み（コード調査・自己完結化）は coff-issue-polish に委ねる。共通事項は coff-detail-issue を単一ソースとして参照する。
-->

## 手順

1. `.claude/skills/coff-detail-issue/SKILL.md` を読み込み、保存先・命名規則・テンプレート・品質基準を把握する。 <!-- skill は自動では相互ロードされないので明示的に読む -->
2. `issue/` ディレクトリが無ければ `mkdir -p issue` で作成する。
3. ユーザーの要望から、テンプレートの「タイトル / 背景・目的 / 変更方針」など分かる範囲を埋める。未確定の項目は空欄かプレースホルダのまま残す（深掘りは polish の役目）。
4. 命名規則でファイル名を採番し、`issue/<name>.md` を作成する。
5. 作成したパスを報告する。続けて磨き込むなら coff-issue-polish skill を案内する。

## 注意

- create は軽い骨組み生成に徹する。重いコード調査や前提検証はしない。
