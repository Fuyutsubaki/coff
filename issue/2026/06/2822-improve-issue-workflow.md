---
status: done
---
# issue ワークフローの役割分担と品質を見直す

## 背景
coff の issue は実装の指示書であると同時に、設計判断の長期記憶でもある。
その issue を作る coff-issue-create / coff-issue-polish / coff-detail-issue が期待どおり働いていなかった。

- create と polish の違いが「完成度の差（素描 vs 調査済み）」で定義され、「何を書くべきか」の差になっていない。結果、create が解決策まで書き込みやすかった。
- create にも polish にも「問題の妥当性（本当に解くべきか・問いの立て方・別の捉え方）」を検証する段が無い。
- polish に「本来ユーザーが決めるべき判断を確定前に聞く」段が無く、推測を仕様として固定してしまう。
- 採用案に対する代替案と却下理由（＝長期記憶として最も価値のある部分）を残す仕組みが無い。

## 決めたこと
役割分担の軸を「完成度の差」から「問題空間 vs 解決空間」へ切り直し、3スキルを協調して書き換えた。

- coff-detail-issue を共通の土台にする。テンプレート各節に担当ラベル（問題／解／横断）を付け、品質基準を create 出口（問題が正しく立つ）と polish 出口（実装着手可）の二段に分け、「問題の妥当性」4観点を定義する。
- coff-issue-create は問題空間（背景・目的／現状）だけを書き、妥当性を吟味し、解決空間はプレースホルダに残す。
- coff-issue-polish は入口で問題空間を点検し（崩れていれば差し戻す）、論点を「コードで答えが出る／ユーザーの判断が要る」に仕分け、後者だけ grilling の規律で確定前に聞く。採用案の代替案と却下理由の記録を必須化し、自己レビューをチェックリスト化する。
- 尋問の型として grilling skill（Matt Pocock, MIT）を vendoring し、polish／create から参照する。
- テンプレートに「人間が決めた判断」節を新設する。polish が強くなるほど AI と人間の判断境界が曖昧になるため、確定済み判断の provenance を本文に残す。

## 却下した代替案と理由
- スキルの役割はそのままで detail／テンプレートを厚くするだけにする。→ create／polish の役割の混線が直らない。
- create を廃し polish 一本にする。→ 「問題を軽く立てる」入口と妥当性検証を失う。issue が設計の長期記憶である以上、問題の立て方を独立した段として残す価値が高い。
- grilling の原理を polish に内蔵し、外部 skill を取り込まない。→ 数行で済むが、grilling を汎用の尋問部品として create や設計時にも再利用したい。配布先で参照が切れないよう実体を同梱したいので vendoring を選んだ。
- GPT Pro が提案した周辺スキル（split-issue / issue-ready-check / to-issues / grill-with-docs 等）。→ create/polish/detail ＋ grilling のスコープを越えるため不採用。1 issue = 1 問題を守る。有用なものは将来別 issue とする。

## 参考
- 完了表記は独立性が高いので別 issue に切り出した: `issue/2026/06/3023-issue-done-status.md`
- vendoring の先例: `issue/2026/06/2803-import-tech-write-ja.md`（japanese-tech-writing の取り込み）
- grilling skill: https://github.com/mattpocock/skills/tree/main/skills/productivity/grilling （MIT, Matt Pocock）
- 実装ソース: `.coff/src/coff-detail-issue.skill.md` / `coff-issue-create.skill.md` / `coff-issue-polish.skill.md`
