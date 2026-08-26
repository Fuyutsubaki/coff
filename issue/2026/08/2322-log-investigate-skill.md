---
status: done   # open（未完了）| done（完了）
---
# Claude Code のセッションログから問題の原因を調査する skill を追加する

## 要約
セッション中に起きた問題の原因を、記憶や差分からの推測ではなくセッションログ（`~/.claude/projects/<project>/<session-id>.jsonl`）から特定する skill `coff-log-investigate` を `.coff/src/` に追加する。
ログの要約と読解は読み取り専用の subagent に委譲し、本体には固定の型の報告だけを返す。
報告は反省の採用 skill（`issue/2026/08/2322-adopt-lessons-skill.md`）の入力になる。

## 背景・目的
セッション中に起きた問題（指示と違う変更をした、手順を飛ばした、同じ失敗を繰り返した、など）の原因を知りたいとき、現状は会話の記憶か git の差分から推測するしかない。
記憶は要約された後に失われ、差分には「なぜそうしたか」が残らない。
Claude Code は各セッションの全発話・ツール呼び出し・結果をログに記録しており、ここには判断の経緯が残っている。
このログを読み、問題が起きた箇所を特定して原因を説明する skill を用意したい。

調査結果の主な使い道は、反省を skill や issue に採用すること（`issue/2026/08/2322-adopt-lessons-skill.md` — 反省の採用 skill）である。採用の入力となる「何が、なぜ起きたか」を信頼できる形で得るのがこの issue の目的。

## 現状
ログの所在と形式（2026-08-24 時点、Claude Code の内部仕様）:

- プロジェクトごとのディレクトリ `~/.claude/projects/<cwd の英数字以外を `-` に置換した名前>/` に、セッション 1 つにつき `<session-id>.jsonl` が 1 つある。例: `/home/fuyutsubaki/coff` → `~/.claude/projects/-home-fuyutsubaki-coff/`。
- subagent の transcript は `<session-id>/subagents/agent-<id>.jsonl` に分かれている（会話行の形式は本体と同じ。`agentId` が付き `isSidechain` が true）。並びの `agent-<id>.meta.json` に `agentType` と起動時の `description` がある。本体のログには subagent の内部は載らない。
- 1 行 1 イベントの JSON。`type` が `user` / `assistant` の行が会話本体で、`timestamp`、`cwd`、`gitBranch`、`isSidechain`、`message.content` を持つ。`message.content` は文字列（人間の入力）か、`text` / `thinking` / `tool_use` / `tool_result` のブロック配列。
- `type` がそれ以外の行（`attachment`、`system`、`file-history-snapshot`、`mode` など）は会話の読解には不要。
- 大きさは 1 セッション数十 KB から数 MB。同プロジェクトの最大で 1.8 MB。全文をコンテキストに載せるのは現実的でない。
- `jq` はこの環境に入っていない。`python3` はある。

既存資産:

- 7/29 のコミット 5475272（セッション振り返りから記録規範 3 件とレビュー skill を採用）では、振り返りをログではなく会話中の記憶をもとに行った。
- coff の既存 skill（`.coff/src/`）にログを読む機能はない。
- `.coff/src/coff-review-diff-code.skill.md` が「読み取り専用の subagent を立て、対象の取得は subagent 自身にさせ、集約だけ本体で行う」構成の先例。
- codex-delegate skill は別プロセスへの委譲先だが、ログの所在や読み方の知識は持っていない。

## 変更方針
`.coff/src/coff-log-investigate.skill.md` を新設する。`coff-dist: true` とし、coff-init の導入リストに加える。

入力は「何が問題だったか」の一文と、任意のセッション指定（セッション ID か日時）。指定がなければ、同プロジェクトのログを更新時刻順に並べ、現在のセッションを除いた最新を対象にする。現在のセッションのログは、この skill の呼び出し自体が直前に書き込まれているので、更新時刻が最新の 1 本がそれに当たる。つまり既定は「更新時刻順で 2 番目」。日時の指定は JST として受け取り、UTC に直して `timestamp` の範囲に含むログを選ぶ（ログの `timestamp` は UTC の ISO 形式）。候補が複数残るときは、各ログについて、文字列型でタグ（`<command-message>` など）で始まらない最初のユーザ入力の冒頭を並べて一問で確かめる。タグ付きしか無ければ `<command-args>` の中身を使う。

手順の骨子:

1. 本体がプロジェクトディレクトリと対象ログのパスを確定し、問題の一文とともに読み取り専用の subagent に渡す。ログ本文は本体で読まない。
2. subagent はまず python3 でログをタイムラインに要約する。1 イベント 1 行で、時刻（JST に変換）・役割・本文冒頭（`text` は先頭 200 字、`tool_use` はツール名と入力の先頭 100 字、`tool_result` は先頭 100 字）だけを出す。`thinking` はここでは落とす。`tool_result` の `content` は文字列と配列の両方があるので、配列なら `text` ブロックを連結して扱う。
3. subagent はタイムラインから問題の前後を特定し、その範囲だけ `thinking` と `tool_result` の全文を読む。必要なら `subagents/` 配下も同様に読む。
4. subagent は固定の型で報告する: 事象（何が起きたか）/ 経緯（時系列、ログの時刻つき）/ 原因（判断のどこが誤ったか。根拠となる発話や thinking を引用。引用は 1 箇所あたり数行まで）/ 教訓候補（規範に落とせそうな一文。なければ「なし」）。
5. 本体は報告をそのまま提示する。修正や採用は行わない。採用するなら反省の採用 skill を案内する。

採用した理由と却下した代替:

- subagent 委譲を採用: ログは大きく、本体で読むと以降の作業のコンテキストを圧迫する。review skill と同じ構成にすれば保守の型も揃う。
- 原因調査を採用 skill の前段に組み込む案は却下: 採用に至らない疑問の解消（「あのとき何故こうしたか」を確かめるだけ）でも使うため、単独で呼べる必要がある。
- codex-delegate への委譲を既定にする案は却下: plugin の有無に依存する。review skill と同様、native subagent を既定にし、別プロセスで動かしたいときの選択肢として注意書きに残す。
- タイムライン要約を skill 内の python3 スクリプトで行うことを採用: jq が無く、ブロック配列の要約は shell では書きにくい。フィールド名への依存は `type` / `timestamp` / `message.content` とブロックの `type` / `name` / `input` / `text` に限る。
- 問題箇所の特定を全文 grep に任せる案は却下: 「手順を飛ばした」のような問題は特定の語で引けない。時系列を俯瞰してから絞る方が確実。

## 実装詳細
触る範囲:

- 新規 `.coff/src/coff-log-investigate.skill.md`。frontmatter は `name` / `description` / `license: MIT` / `coff-dist: true`。description は「セッションログから問題の原因を調査し、固定の型で報告する。修正はしない」の趣旨。
- `.coff/src/coff-init.skill.md` の手順 2 の対象一覧に `coff-log-investigate` を追加。
- ビルドは `/compile`（`.claude/skills/` と `skills/` ミラーに出る）。

skill 本文に含めるもの:

- 対象ログの決め方（上記方針の入力規則）と、プロジェクトディレクトリ名の導出規則。
- タイムライン要約の python3 スクリプト。ヒアドキュメントで skill に埋め込み、標準出力にタイムラインを出す。subagent はこれを実行してから読む。
- subagent への指示文の要点: 読み取り専用、ファイルを変更しない、報告の型、推測と根拠を分けて書くこと。起動は native の Agent ツールの Explore 型（Bash はあり、Edit と Write が無い）で、読み取り専用をツール構成でも担保する。
- 報告の型（事象 / 経緯 / 原因 / 教訓候補）。反省の採用 skill はこの型を前提に読む。

書き方は既存 skill に合わせ、端的な指示形で書く（冗長な説明や造語ラベルを避ける）。

## 検証
- [x] `/compile coff-log-investigate` が成功し、`.claude/skills/coff-log-investigate/SKILL.md` と `skills/coff-log-investigate/SKILL.md` が生成される — 確認: 両パスの存在と `coff-init` の一覧に名前があること
- [x] 埋め込んだ python3 スクリプトが実在のログで動く — 確認: `~/.claude/projects/-home-fuyutsubaki-coff/` の最大のログ（約 1.8 MB）に対して実行し、エラーなく 1 イベント 1 行のタイムラインが出ること
- [x] 実セッションで原因が特定できる — 確認: `f6586fef-…jsonl`（7/26〜7/31、振り返りの元セッション）をセッション ID で指定し、`issue/2026/07/2700-record-reasons-verbatim.md` の背景にある「却下理由を別の理由に言い換えた」事象を一文で与え、報告の「原因」に該当の発話の引用が含まれること
- [x] 本体がログ本文を読まない — 確認: 上の実行で、本体側のツール呼び出しにログファイルを対象とする Read / cat が無いこと（本体の transcript を python3 のタイムライン要約で確認する）
- [x] 既定の対象選択が現セッションを除く — 確認: セッション指定なしで呼び、選ばれたログが更新時刻順で 2 番目であること
- [x] 報告が固定の型に従う — 確認: 事象 / 経緯 / 原因 / 教訓候補の 4 節が揃っていること

## 人間が決めた判断
- 2026-08-23: 依頼時点では「ログ調査」と「反省の採用」を 1 つの要望として挙げた。採用・完了を独立に判断できるため 2 issue に分割した（分割は AI の提案。人間の明示の指示ではない）。

## リスク・未解決
- ログ形式は Claude Code の内部仕様で、バージョンで変わりうる。スクリプトが依存するフィールドは最小にするが、壊れたときは skill 側を直す前提。
- コンテキスト圧縮（compaction）が起きたセッションで、圧縮前の経緯がログにどう残るかは未確認（手元のログに該当例がない）。検出の手がかりは skill に書かず、経緯に不自然な飛びがあれば報告にその旨を書くに留める。
- 問題が subagent 内で起きた場合、本体ログからは結果しか見えない。`subagents/` を読む手順は入れるが、どの subagent かの特定は `meta.json` の `description` と時刻の突き合わせに頼る。
- 「現在のセッション以外で最新」という既定は、調査したい問題が今まさに起きたセッション（自分自身）の場合に外れる。その場合はセッション ID の明示を求める。
- coff-init の導入一覧は `coff-dist: true` の skill だけを載せる慣行（codex-delegate は載っていない）。この skill は dist 対象なので載せる。

## 参考・関連 issue
- `issue/2026/08/2322-adopt-lessons-skill.md` — 調査結果を skill/issue に採用する skill
- コミット 5475272 — 手作業で行った振り返り → 採用の先例
- `.coff/src/coff-review-diff-code.skill.md` — subagent 委譲構成の先例
- `.coff/src/codex-delegate.skill.md` — 別プロセスで動かすときの委譲先
