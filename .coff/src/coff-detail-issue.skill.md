---
name: coff-detail-issue
description: issue 管理の共通事項（保存先、命名規則、テンプレート、品質基準）を提示する。
---

<!--
issue 関連の共通事項の唯一の参照元。coff には skill 間の include がないため、共通事項はここに集約し、coff-issue-create / coff-issue-polish は実行時に `.claude/skills/coff-detail-issue/SKILL.md` を読み込んでこれを参照する。重複は各 skill に書かない。
-->

## 直接呼び出し時の動作

`/coff-detail-issue` が直接呼ばれたときは、以下の保存先、命名規則、テンプレート、品質基準を提示するだけにとどめる。issue の生成も編集もしない（生成は coff-issue-create、磨き込みは coff-issue-polish の役目）。

## 保存先と命名

- issue はリポジトリ内の `issue/` ディレクトリに置く。1 件の issue につき 1 つの Markdown ファイルとする（GitHub Issues は使わない）。
- ファイル名は `yymmddHH-<slug>.md`。`<slug>` は内容を表す短いケバブケース（例 `fix-hoge`、`add-login`）。
- ファイル名の例:

  ```bash
  ts="$(date +%y%m%d%H)"   # 例: 26062814
  # <slug> は内容を表す短いケバブケース。例: fix-hoge
  # -> issue/26062814-fix-hoge.md
  ```

## 言語

issue 本文は日本語で書く。日本語は japanese-tech-writing skill の規範に従って書く。

## テンプレート

新規 issue は次の構成で書く。目標は「この issue 単体で実装に着手できる」こと。

```markdown
# <タイトル: 命令形で簡潔に>

## 背景・目的
<なぜ必要か / 解きたい問題>

## 現状
<今どうなっているか・関連する既存の挙動>

## 変更方針
<どう変えるか・採用案とその理由>

## 対象範囲・対象ファイル
<触る範囲。代表的なファイルパス>

## 実装詳細
<手順・データ構造・インターフェース。単体で実装できる粒度で>

## 受け入れ条件
- [ ] <完了の定義をチェックリストで>

## テスト方針
<どう検証するか>

## リスク・未解決
<懸念・要判断点・代替案。未確定はここに明示する>

## 参考・関連 issue
<リンク・関連する issue/ ファイル>
```

## 良い issue の基準

- 判定軸は「この issue 単体で実装に着手できるか」。
- 曖昧語や未確定事項を本文に残さない。残すものは「リスク・未解決」に明示する。
