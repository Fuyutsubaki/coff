---
status: done
---
# issue に完了（done）を表す仕組みを追加する

## 背景
issue を作った後、完了を表す手段が無かった。
coff の issue は実装の指示書であると同時に、設計判断の長期記憶でもある。
だから完了したものは削除せず、完了と明示したうえで記録として残せる必要がある。

## 決めたこと
完了状態を各 issue の YAML frontmatter に `status`（`open` / `done` の2値）で持たせる。
ファイルは元の場所に残し、パスは変えない。

- ファイルが動かないので issue 間のパス相互参照が壊れず、「完了しても記録として残す」長期記憶の目的に整合する。
- `grep 'status: done' issue/*.md` で機械的に一覧できる。
- frontmatter または `status` が無い issue は `open` とみなす。既存 issue を遡及で触らずに済ませるための既定。
- 新規 issue は coff-issue-create が `status: open` を付け、完了時に専用スキル coff-issue-done が `done` へ更新する。polish は上書き時に frontmatter を保存する。

## 却下した代替案と理由
- 完了 issue を `issue/done/` へ移動する。→ パス相互参照が壊れ、完了済みの設計記録が主一覧から隠れる。長期記憶の目的に反する。
- 本文先頭に `> 状態: 完了` のマーカー行を置く。→ 書式が緩く揺れやすく、機械集計が弱い。
- 値域を `todo/doing/done/rejected` まで広げる。→ 現時点の必要は完了か否かだけ。YAGNI で2値に絞った（`doing`・`rejected`・完了日は必要が顕在化したら別 issue で拡張）。
- done 化を手編集の運用規約だけで済ませる。→ 完了マークの操作を手順として明示・再現したいので、専用スキルを新設した。

## 参考
- `issue/26062822-improve-issue-workflow.md`（本 issue はここから切り出した）
- 実装: `.coff/src/coff-detail-issue.skill.md`（status 仕様）/ `coff-issue-create` / `coff-issue-done` / `coff-issue-polish`
