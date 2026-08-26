---
status: done   # open（未完了）| done（完了）
---
# セッションの反省を skill や issue に採用する skill を追加する

## 要約
セッションの反省を「skill の規範に追記する / issue に起こす / 採用しない」に仕分け、採用するものを実際に `.coff/src/` への追記か issue 起票まで進める skill `coff-adopt-lessons` を追加する。
判定基準は、7/29 の手作業の先例でユーザが示した指示（必要か否かで判断する、既存実装や設計判断との衝突を点検する、元の発言に当たる）を skill に移して恒久化する。
衝突や判断が要る候補は勝手に採用せず、人間に提示する。

## 背景・目的
セッションを終えたあと「次は〜すべきだった」という反省が出ても、会話の中に留まるだけでは次のセッションに引き継がれない。
反省を恒久化するには、coff の規範として `.coff/src/` の skill に書く、または作業単位として issue に起こす必要がある（採用先を memory ではなく skill にする方針は既に決めている）。
この「反省 → 採用先の判断 → skill 追記 / issue 作成」の手順を skill にして、毎回同じ品質で行えるようにしたい。

## 現状
- 7/29 のコミット 5475272 で、セッション振り返りから記録規範 3 件を既存 skill に追記し、レビュー skill を 1 件新設した。issue 4 件を起こして done にした（`issue/2026/07/2700-record-reasons-verbatim.md` など）。手順はその場で組み立てたもので、skill として残っていない。
- そのときユーザが示した採用の判定基準は、ユーザローカルの memory（`coff-adoption-goes-to-skills-not-memory`）にだけ残っている。内容は次の通り。
  - 採用先は `.coff/src/` の skill ソース。memory への追加は採用手段にしない（coff は配布物で、memory は配布されない。2026-07-26 のユーザ指示）。
  - 候補はまず「必要か否か」で判断する。必要なら置き場は作ってよく、「既存 skill に置き場がない」は却下理由にならない（2026-07-27 のユーザ指示）。
  - 既存 skill に実装済みでないか、記録済みの設計判断と衝突しないかを点検する。
  - AI が生成した振り返り一覧は元の意図が曲解されていることがある。却下する前に元の発言に当たる。
- 1 issue = 1 意図の分割規範と、判断の記録規範（発話の語彙のまま書く）は `.coff/src/coff-detail-issue.skill.md` にある。
- 反省の入力は、会話の記憶か、セッションログの調査（`issue/2026/08/2322-log-investigate-skill.md` — ログから原因を調査する skill）のどちらか。後者は報告の型（事象 / 経緯 / 原因 / 教訓候補）を持つ。
- issue の作成は coff-issue-create、skill のビルドは `/compile`（coff 以外の導入先では `/coff-compile`）が担う。
- 導入先 repo でも自作 skill は `.coff/src/` に置く規約になっている（coff-init が案内する）。

## 変更方針
`.coff/src/coff-adopt-lessons.skill.md` を新設する。`coff-dist: true` とし、coff-init の導入リストに加える。

入力は反省の一覧。形式は問わない（会話中の箇条書き、ログ調査 skill の報告、ユーザの一言）。本体セッションで実行する（手順 1 で会話中の発言に当たるため。subagent に委譲しない）。

手順の骨子:

1. 反省を 1 件ずつ「元の発言」と突き合わせる。発言が会話中にあれば引用し、無ければ（AI が要約した一覧だけの場合）ユーザに元の意図を一問で確かめる。
2. 各件を次の 3 つに仕分ける。
   - 規範にする: 同種の失敗が繰り返される構造的な問題で、手順や判定基準の一文として書けるもの。採用先は既存 skill の該当箇所。無ければ新設してよい。
   - issue にする: 規範の一文では済まず、実装や構造の変更が要るもの。
   - 採用しない: 一度きりの事故、既存 skill に実装済みのもの。

   記録済みの設計判断と衝突する件は、衝突先を添えて提示し、どちらを取るかは人間が決める。
3. 仕分けと理由を一覧にして提示し、人間の採否を得る。理由はユーザの語彙のまま記録する。ここまでは `.coff/src/` に触れない。
4. 採否が出てから採用分を実行する。規範にする分は、1 件ずつ問題空間だけの issue を coff-issue-create で起こし、`.coff/src/` に追記してビルドし、coff-issue-done で閉じる（すべての変更は issue を通す規範に従う。polish は通さない。coff-detail-issue の受け入れ基準「単体の小さな変更は、数行の問題空間だけの issue を起こして直ちに done にしてよい」に当たる）。issue にする分は coff-issue-create で起票して終える（polish 以降は別途）。
5. 結果（追記先、起票した issue、採用しなかった件と理由）を報告する。

採用した理由と却下した代替:

- 判定基準を skill に書くことを採用: 今は memory にあり、配布されず、coff 本体の改善になっていない。memory 自身が「知見は skill に置く」と言っている。
- 反省の採用を coff-issue-create に吸収する案は却下: create は問題を立てる skill で、「採用するか」「規範か issue か」の仕分けは問題を立てる前の工程。create に入れると create が肥大し、反省以外の起票でも仕分けを通ることになる。
- ログ調査を前段に組み込む案は却下: 入力はログ調査の報告に限らない。会話中の反省をそのまま渡せる必要がある。ログ調査は別 skill として案内するに留める。
- coff リポジトリ専用にする案は却下: 導入先でも `.coff/src/` に自作 skill を置く規約があり、採用先の決め方は同じ。ビルドコマンド名だけ異なる（`/compile` は coff のラッパー、導入先は `/coff-compile`）ので、skill では `/coff-compile` を基本にし、ラッパーがあればそれを使うと書く。
- 仕分けを AI が決めて即実行する案は却下: 採否と理由の記録は人間の判断で、AI が決めると理由の言い換えが起きる（7/29 の `issue/2026/07/2700-record-reasons-verbatim.md` の事故）。提示 → 採否の段を必ず挟む。

## 実装詳細
触る範囲:

- 新規 `.coff/src/coff-adopt-lessons.skill.md`。frontmatter は `name` / `description` / `license: MIT` / `coff-dist: true`。description は「セッションの反省を skill の規範か issue に仕分けて採用する」の趣旨。
- `.coff/src/coff-init.skill.md` の手順 2 の対象一覧に `coff-adopt-lessons` を追加。
- memory `coff-adoption-goes-to-skills-not-memory` の内容が skill に移ったら、memory 側は skill への参照に縮める（これは coff の成果物ではないので、ビルドの対象外。実装者の手作業）。

skill 本文に含めるもの:

- 仕分けの 3 区分とそれぞれの判定基準、設計判断と衝突する件の扱い（上記方針の手順 2）。
- 「元の発言に当たる」手順と、無いときの一問の聞き方（推奨案つき、一問ずつ）。
- 提示の型: 1 件 1 行で「反省 / 仕分け（規範・issue・不採用）/ 採用先または却下理由（衝突があれば衝突先も）」。
- 採用後の実行手順は、coff-issue-create と coff-compile を参照で指す。手順の写しは書かない。
- 入力としてログ調査 skill `coff-log-investigate` の報告（教訓候補の節）を受け取れることを一文で書く。その skill は `issue/2026/08/2322-log-investigate-skill.md` で未実装だが、名前は確定しているので先に書いてよい。

書き方は既存 skill に合わせ、端的な指示形で書く。

## 検証
- [x] `/compile`（引数なし。coff-init も再ビルドするため）が成功し、`.claude/skills/coff-adopt-lessons/SKILL.md` と `skills/coff-adopt-lessons/SKILL.md` が生成される — 確認: 両パスの存在と、ビルド後の `coff-init` 成果物の一覧に名前があること
- [x] skill に memory の 4 つの判定基準（採用先は `.coff/src/`、必要か否かで判断、既存実装と設計判断の衝突点検、元の発言に当たる）がすべて含まれる — 確認: skill 本文を読み、各項目に対応する記述を指せること
- [x] 先例で再現できる — 確認: 7/29 の振り返り 4 件の「背景・目的」を反省として与えて skill を動かし、提示の段で次の仕分けになること。`2700-record-reasons-verbatim` と `2701-master-view-record` は規範（採用先 coff-detail-issue）、`2700-whynot-relevance-check` は規範（採用先 coff-issue-polish）、`2700-review-diff-code` は issue（新 skill の新設）。採用先は人間の採否の前の提案として評価し、実行まではしない
- [x] 人間の採否を経ずに `.coff/src/` が変更されない — 確認: 仕分けの提示後に採否を求める手順が skill にあること

## 人間が決めた判断
- 2026-08-23: `issue/2026/08/2322-log-investigate-skill.md` と分割して起票（分割は AI の提案）。
- 2026-08-25: 差分レビューの指摘を「じゃあその推奨通りで」で採用。区分は 3 つにして衝突は注記に落とす、「判断の記録」規範は coff-detail-issue への参照に縮める（二重管理を避ける）、「本体セッションで実行」は skill 本文に明文化。レビュー観点の統合などの既存部分への指摘は見送り。memory `skill-prose-terse-imperative` の skill 化は次セッションで coff-adopt-lessons に渡す。
- 2026-08-24: この skill は coff 前提でよい（`.coff/src/` と coff の issue 運用を前提にする）。汎用化（coff 未導入 repo でも動く形）は提案したが「coff を前提とするのはあってる」として不採用。

## リスク・未解決
- 「issue を通す」規範と「反省採用を軽く回したい」要望の間で、規範 1 件ごとに issue を起こす手間が残る。先例（4 件で issue 4 件）と同じ運用なので受け入れるが、重いと感じたら detail の受け入れ基準ごと見直す。
- 「構造的な問題」と「一度きりの事故」の線引きは判定者の裁量が残る。skill には判定の問い（「同じ状況で同じ失敗が再び起きるか」）を置くに留め、境界例は人間に提示する。
- 反省が既存の設計判断と衝突するとき、どの issue の判断と衝突するかを探す手間がかかる。skill の frontmatter コメント（設計判断の出典 issue を書く慣行）を手がかりにする。
- memory を縮める作業はユーザローカルの変更で、PR には入らない。done の確認で見落とさないよう検証には含めないが、実装詳細に残す。

## 参考・関連 issue
- `issue/2026/08/2322-log-investigate-skill.md` — ログから原因を調査する skill。報告の型がこの skill の入力になる
- コミット 5475272 と `issue/2026/07/2700-record-reasons-verbatim.md` ほか — 手作業で行った先例
- `.coff/src/coff-detail-issue.skill.md` — 1 issue = 1 意図、判断の記録規範
- `.coff/src/coff-issue-create.skill.md` — issue 起票の呼び先
- `.coff/src/coff-init.skill.md` — 導入リスト
