---
name: coff-review-diff-code
description: 現在のブランチの差分を、観点ごとの subagent を立てた固定 6 観点でレビューし、指摘を集約して報告する。修正はしない。
license: MIT
coff-dist: true
---

<!--
done 前に手打ちで繰り返されていた観点別レビューの skill 化。実行系は native subagent 既定（plugin 依存を避ける。issue/2026/07/1518-polish-implementer-sim.md と同じ判断）。観点構成と対象の判断は issue/2026/07/2700-review-diff-code.md。
-->

## 手順

1. レビュー対象を確定する。基底ブランチは `origin/HEAD` が指す既定ブランチ、無ければ master / main のうちローカルに存在する方。対象は基底と作業ツリーの差分と、未追跡ファイル。差分が空ならその旨を報告して終える。

   ```bash
   base=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)   # 例: origin/master
   if [ -z "$base" ]; then
     for b in master main; do git show-ref --verify -q "refs/heads/$b" && { base=$b; break; }; done
   fi
   git diff --stat "$base" && git status --short --untracked-files=all
   ```

2. 観点ごとに subagent を並列に起動する。subagent は読み取り専用で動かし、ファイルの修正はさせない。各 subagent には基底ブランチ名と担当観点だけを渡し、差分は subagent 自身に取得させる（`git diff <base>` で作業ツリーとの差分を取り、`git status --short --untracked-files=all` に挙がる未追跡ファイルは直接読む。大きい差分をプロンプトに埋め込まない）。観点外の指摘はさせない。

   観点:

   1. 一般的なレビュー観点（正しさ、既存規約との整合、退行）
   2. YAGNI（未使用の拡張点、上位で担保済みの再チェック、起き得ない保険）
   3. 仕様は無意味に複雑ではないか
   4. issue は複雑すぎないか（差分に含まれる issue が変更の実体と釣り合っているか）
   5. 同種アンチパターンの横展開漏れ（差分で直した問題と同種のものが差分の外に残っていないか。差分外の探索は同種パターンの検索に限る）
   6. 入口 artifact の実在と薄さ（依頼された入口が作られているか、仕様の写しで肥っていないか）

   観点 4 と 6 は判定材料を差分内の issue ファイルに求め、無ければ「対象なし」と返す。

3. 指摘を集約して報告する。同一箇所・同一趣旨の指摘は一つにまとめ、正しさに関わる指摘を先に、観点と該当箇所（パス:行）つきで並べる。修正はせず、採否は呼び出し元に委ねる。

## 注意

- codex-delegate skill が導入されていれば、それに委譲して別プロセスで回せる。
