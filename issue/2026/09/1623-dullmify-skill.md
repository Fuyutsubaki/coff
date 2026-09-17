---
status: open
---
# skill をワークフロー部分と LLM 部分に分ける skill dullmify を作り、coff-compile から呼べるようにする

`/coff-dullmify <name>` が skill ソースを、決定論的な Perl の workflow と薄い SKILL.md に分けて出力する。LLM が作るのは workflow 本体と topic 節だけで、土台と定型は雛形を複製する。
制御をプログラムに移し、LLM は問われた判断にだけ答える形にして、トークン消費と想定外の挙動を減らし、事前承認をプログラム呼び出しだけに絞る。
coff-compile は `coff-dullmify: true` のソースで `/coff-dullmify` を呼ぶ。最初の適用先は coff-compile 自身とする。

## 目的

coff の skill は、手順の制御と LLM にしかできない判断（文の要否の判定、翻訳、ユーザーへの問い）を一つの Markdown に混ぜて書いている。
制御まで LLM が読んで実行するため、手順の記述が毎回トークンを消費し、ファイル操作を LLM が行うので事前承認を絞れず、手順が長いほど読み飛ばしや順序違いが起きる。
本 issue の目的は、宣言した skill について制御の主体をプログラムに移し、LLM の役割を判断への回答に限ることである。LLM から Write / Edit を強制的に取り上げることは扱わない。

## 現状

- coff-compile は `.coff/src/*.skill.md` を `.claude/skills/<name>/SKILL.md` に出力する。成果物は Markdown だけで、コードを含める機構はない。ビルド指示は frontmatter の `coff-*` で宣言し、skip 判定は出力先の最終行のフッタの md5 で行う。
- LLM が bash スニペットを読んで制御を担っているソースは coff-compile、compile、coff-init、coff-review-diff-code の 4 つ。coff-issue-list は awk の埋め込みコマンドと `allowed-tools` で既にプログラム化されている。
- Claude Code の `allowed-tools` は skill のターンで列挙したツールを事前承認する機構で、列挙外を制限しない。`${CLAUDE_SKILL_DIR}` で skill ディレクトリ基準のパスを書ける。Bash ツールは起動済みプロセスの stdin に書けない（調査記録 1）。
- 配布の単位は skill ディレクトリで、`gh skill install` はサブディレクトリごとコピーする。ラッパー compile のミラー同期は SKILL.md 単体の複製で、issue/2026/08/0501-coff-include-directive.md（skill 同梱のビルド指示。未着手）がディレクトリ単位への拡張を予定している。

## 設計方針

**1. dullmify は独立 skill `coff-dullmify` とし、coff-compile はそれを呼ぶ。**
`/coff-dullmify <name> [--out <dir>]` は `.coff/src/<name>.skill.md` を読み、`scripts/workflow.pl`（workflow 本体）と薄い `SKILL.md`（ソースの言語のまま）を出力する。既定の出力先は `.claude/skills/<name>/`。
coff-compile は `coff-dullmify: true` のソースで、topic `dullmify` を LLM に問い、薄い coff-compile skill が `/coff-dullmify <name> --out <staging>` を実行して答える。coff-compile の Perl は staging の出力を読み、英訳とコメント除去とフッタを施して bundle と共に原子的に公開する。生成規則の正本は coff-dullmify 1 箇所で、Perl 同士の依存は作らない。

**2. LLM が作るのは workflow 本体と topic 節だけ。土台と定型は雛形を複製する。**
coff-dullmify は runtime `Coff::Workflow`、汎用 driver `scripts/run.pl`（同じディレクトリの `workflow.pl` を読んで `run_workflow` を呼ぶ）、薄い SKILL.md の定型（往復の手順、`status` / `cancel` / `gc`、終了の報告）を同梱し、生成物にそのまま差し込む。LLM への問いは 2 つ。`workflow` は `sub workflow` と固有の補助関数だけを返し（既存の `workflow.pl` を渡して必要な変更に限る）、`topics` は topic ごとの判断基準の Markdown だけを返す。組み立て、`perl -c`、書き出しは coff-dullmify の Perl が行う。

**3. runtime の API は本体が読める形にする。** `step` は block だけを取り、識別は実行順で行う。入力を明示するのは LLM に送る `llm` / `user` だけ。失敗は `die` で表し、runtime が中断（Suspend）と失敗を見分ける。複数対象を回す workflow のために、Suspend を再送出しつつ失敗だけを捕まえる `attempt` を runtime が提供する。
実行モデルは変えない: 毎回起動、状態は journal、`start` で run と effect の索引つきの問いを返し、答えは stdin で `resume <run> <index>` に渡す。effect の順序と入力ハッシュ、`workflow.pl` と runtime の md5 を検証し、journal の値と workflow に返す値は JSON の往復で切り離す。

**4. 薄い skill の `allowed-tools` はプログラム呼び出しだけ。** `Bash(perl ${CLAUDE_SKILL_DIR}/scripts/run.pl *)` のみを書き、書き出しは Perl に寄せる。列挙外ツールを禁止する機構は追加しない。

**5. 最初の適用先は coff-compile 自身。** coff-dullmify 自体は最初から「薄い skill ソース + 手書きの Perl」で書き、自分を生成しない。compile / coff-init / coff-review-diff-code の変換は別 issue。

却下した代替案:

- coff-compile のソースに生成規則を置き、毎ビルド LLM が土台ごと Perl を書く（初回の実装）: 生成物の半分が土台と入力の書き写しで読めず、規則の正本が coff-compile に埋まる。
- coff-compile の Perl から coff-dullmify の Perl を直接呼ぶ: 往復は 1 回減るが Perl 同士の依存ができる。skill から skill を呼ぶ形を採る。
- 常駐プロセスとの往復（名前付きパイプ、MCP サーバー、`claude -p` の逆転）: Bash ツールが起動済みプロセスの stdin に書けない。MCP は skill ごとの登録が配布と合わず、逆転は会話文脈と権限を引き継げない。
- `context: fork` とツールを絞った agent で Write / Edit を外す: AskUserQuestion が使えず、承認を挟む skill が成立しない。

## 決めたこと

- 言語は一旦 Perl。Go は採らない（元は skill とプロセスが標準入出力で処理する想定だったが、それには生きているプロセスと会話する必要があり、skill はそれには不十分だった。その前提では Go はわざわざインストールを要求するほど便利ではなかった）
- dullmify は独立した skill にし、その上で coff-compile の選択肢にする（初回実装の「coff-compile の工程」を差し替え）
- 全 skill で同じになる部分は毎回 LLM で作らず、あらかじめ作った雛形を差し込む（初回実装の生成コードがあまりにも読みづらい）
- coff-compile から dullmify へは LLM 経由（topic `dullmify` で `/coff-dullmify` を実行）で呼ぶ。Perl 同士の依存は作らない
- 権限は「プログラム呼び出しの事前承認と書き出しの移譲」まで。強制はしない
- 最初の適用先は coff-compile 自身

## 完了条件

- [ ] `Coff::Workflow` が block だけの `step`、`die` による失敗、`attempt`、start / resume / status / cancel / gc、非決定の検出、バージョンの固定、再送への冪等を持ち、テストが通る
- [ ] `/coff-dullmify coff-compile --out <dir>` が `scripts/run.pl`、`scripts/workflow.pl`、`scripts/lib/Coff/Workflow.pm`、薄い `SKILL.md` を出力し、`run.pl` と runtime と SKILL.md の定型部分は同梱の雛形とバイト一致する
- [ ] `workflow.pl` が `perl -c` を通らないときは `failed` になり、出力先が変わらない
- [ ] coff-compile が `coff-dullmify: true` のソースで topic `dullmify` を問い、staging の出力に英訳・コメント除去・フッタを施して bundle と共に公開する
- [ ] 薄い SKILL.md は `allowed-tools` が `run.pl` の呼び出しだけで `coff-*` キーが残らず、本文に bash スニペットと制御の手順が無い
- [ ] coff-compile 自身の `workflow.pl` に土台と入力の書き写しが無く、`step` が block だけで書かれている
- [ ] 薄い成果物で `/compile --force coff-compile` を承認プロンプトなしで完走できる（lint 候補の提示、承認、dullmify、英訳、書き出し、レポート）
- [ ] 配布ミラー `skills/coff-compile/` と `skills/coff-dullmify/` が正本とディレクトリ単位で一致する

## 実装メモ

### 実装詳細

- `.coff/src/coff-dullmify/scripts/lib/Coff/Workflow.pm`：runtime（coff-compile から移す）。`step` を block だけに、失敗を `die` に、`attempt` を追加
- `.coff/src/coff-dullmify/scripts/run.pl`：汎用 driver。同じディレクトリの `workflow.pl` を読んで `run_workflow` を呼ぶ
- `.coff/src/coff-dullmify/scripts/dullmify.pl`：coff-dullmify 自身の workflow（手書き）。ソース読み込み、`workflow` / `topics` の問い、雛形との組み立て、`perl -c`、書き出し
- `.coff/src/coff-dullmify/templates/`：薄い SKILL.md の定型
- `.coff/src/coff-dullmify/t/`：runtime と組み立ての テスト
- `.coff/src/coff-dullmify.skill.md`：薄い skill ソース（`workflow` / `topics` の判断基準）。`coff-bundle: [scripts, templates]`、`coff-dist: true`
- `.coff/src/coff-compile.skill.md`：生成規則を削り、`coff-dullmify: true` の処理を「topic `dullmify` を問う」に置き換える。runtime の同梱元を coff-dullmify に変える
- `.coff/src/coff-compile/scripts/`：runtime を coff-dullmify へ移した後は削除。coff-compile の bundle は不要になる
- `.coff/src/compile.skill.md`：変更なし（ディレクトリ単位同期は済み）
- `.claude/skills/coff-compile/`、`.claude/skills/coff-dullmify/`、`skills/`：ブートストラップ成果物とミラー

後で効く制約:

- Perl は 5.30 以上の構文と core モジュールだけを使い、生成する `workflow.pl` は `use utf8` を宣言する（非 ASCII の文字列リテラルが JSON 出力で二重にエンコードされる）。
- `workflow.pl` は `sub workflow` と固有の補助関数だけ。use 群、FindBin、`run_workflow` の呼び出しは `run.pl` にあり、生成しない。
- 副作用は `step` に置き、時計と乱数を使わず、hash のキーを sort する。effect を素の `eval {}` で囲まない。失敗を捕まえるときは runtime の `attempt` を使う（Suspend を再送出する）。
- 問いは `{"run":…,"index":…,"ask":{"topic":…,"kind":"llm"|"user","input":…}}`、終了は `{"run":…,"done":true,"report":…}` とする。
- `resume` の stdin は UTF-8 の文字列として保存し、JSON を要求する topic だけを workflow 側で decode する。
- topic `dullmify` の入力は `{source, name, out}` で、答えは `ok` か失敗の理由。staging の中身を LLM に運ばない。
- lint 候補は `{start, end, replacement, label}` の JSON 配列とし、承認された索引だけをソースへ適用する。
- 全出力を出力先と同じディレクトリへ一時保存し、検査後に rename する。失敗時は backup から既存出力を戻す。
- journal は `workflow.pl` と `Workflow.pm` の md5、effect の順序と入力ハッシュを持つ。journal に入れる値と workflow に返す値は JSON の往復で切り離す（同じ参照を共有すると workflow 側の書き換えが記録に混ざり、replay が非決定として止まる）。
- `done` と `cancel` は journal を終端結果に置き換え、`status` は未回答の問い、`gc` は 7 日より古い run を扱う。

### 完了条件の確認手段

1. `prove -I .coff/src/coff-dullmify/scripts/lib .coff/src/coff-dullmify/t/`
2. `/coff-dullmify coff-compile --out <一時dir>` の後、`ls` で 4 ファイルを確認し、`cmp` で `run.pl` と `Workflow.pm` を同梱元と比べ、SKILL.md の定型段落を `diff` で雛形と比べる
3. 組み立て関数をテストで叩く（壊れた workflow 本文を渡すと失敗が返り、出力先が作られず、既存があれば変わらないこと）。1 のテストに含める
4. 5 の実行中に topic `dullmify` の問いが出て、`/coff-dullmify` の実行後に `translate` の問いが続くことを見る。完走後に `tail -n1` でフッタ md5 が `md5sum .coff/src/coff-compile.skill.md` と一致する
5. `head` で frontmatter を見る。本文は `grep -c '```' .claude/skills/coff-compile/SKILL.md` が 0 で、読んで制御の手順が無いこと
6. `.claude/skills/coff-compile/scripts/workflow.pl` を読む。`use` 行と `run_workflow` が無く、`step {` の直後に hash の引数が続かないこと
7. 初回は `.coff/src/coff-compile.skill.md` を直接読んで手順として実行し、成果物を作る（壊れたら `git restore .claude/skills/coff-compile`）。次に薄い成果物で `/compile --force coff-compile` を実行し、lint 候補の提示から `compiled` の報告までを一度通す。途中で Bash の承認プロンプトが出ないことを見る（出れば `allowed-tools` の前方一致が heredoc に効いていない）。Bash を広く許可したセッションや auto mode では判別できないので、通常の権限設定のセッションで行う
8. `diff -r .claude/skills/coff-compile skills/coff-compile` と `diff -r .claude/skills/coff-dullmify skills/coff-dullmify`

### 調査記録

1. Claude Code docs（https://code.claude.com/docs/en/skills.md 、同 tools.md。2026-09-17 確認）: `allowed-tools` は skill のターンの事前承認で、列挙外のツールは通常の権限設定のまま使える。指定子は settings の permissions と同じ（`Bash(git add *)` 形）。`${CLAUDE_SKILL_DIR}` は skill ディレクトリに展開され、スクリプトは `scripts/` に置くのが慣習。`context: fork` と `agent` で subagent 実行にできる。Bash ツールはバックグラウンドプロセスに EOF を渡し、後から stdin に書く手段はない。
2. 依頼者の事前検討（2026-09-16）の要点:
   - 状態の置き場は「LLM 側」でも「VM のスタック保存」でもなく、プログラム側のファイル。再開に要るのは命令位置ではなく「どの工程にいて、どの値を持つか」なので、LLM 待ちの位置だけを停止点にすれば足りる。
   - 明示的な状態機械（`pc` と switch）は生成コードが読めなくなる。逐次コードを毎回先頭から実行し、記録済みの effect は結果を返すだけにする replay 方式（Temporal / DBOS / Restate 型）なら、`if` / `for` / `while` がそのままワークフロー記述になる。
   - Perl での実現: `llm` は journal に答えがなければ `die` で workflow 全体から脱出する（例外を継続の代用にする）。effect の識別は実行順で足り、ループの反復番号も生成コードに出ない。再生時に順序と入力ハッシュを照合し、食い違えば非決定として止める。文脈は `local` の動的スコープで渡し、深い関数からも引数なしで届く。`step (&)` の prototype でブロック構文にできる。
   - 採らない Perl の手段: source filter（文字列の書き換えで corner case を背負う）、`Keyword::Simple` / `XS::Parse::Keyword`（experimental、XS 依存は配布と逆方向）、Coro（最終リリース 2020 年）、`Future::AsyncAwait`（同一プロセス内の中断にしか効かず、プロセスをまたぐなら結局 replay が要る）。
   - runtime に最低限持たせる 3 点: 再開の検証（run と effect の索引、現在の工程を照合し、LLM に次の工程を指定させない）、重複への対処（同じ答えの再送で二重に進めない。外部への書き込みは冪等にする）、バージョンの固定（開始時の workflow を特定し、更新後の別コードで古い状態を再開しない）。
   - プロセスの終了と workflow の終了を分ける。前者で一時領域を消さない。後者は done / failed / cancelled の終端処理として記録し、`cancel` と `gc` を持つ。
   - Claude Code の Dynamic workflows（Workflow ツール）は近いが、スクリプト自身がファイル操作とシェル実行をできず、外部操作を agent に戻す設計なので採らない。
   - 配布は Perl 同梱の Linux / macOS を前提にし、PAR::Packer による単体実行ファイル化は採らない。
3. 試作（2026-09-17、scratchpad、約 40 行の Perl 5.34）: `die` による中断、journal への保存、`resume` での答えの差し込み、journal のキー改変による非決定の検出が成立した。
4. 先行例: SkillSmith（skill を deterministic / LLM / reference に分解して DAG に落とす。ループは DAG に持たず agent に戻す）と Rote（trevhud/rote。SKILL.md → pipeline.yaml → 実行基盤向けコード）。どちらも「LLM を要する箇所で親の Claude に戻し、同じ workflow を再開する」実行モデルは持たない。SkillSmith の「すべての skill を workflow にせず、曖昧なら元 skill に fallback する」分類は、宣言のないソースを従来どおりビルドする形で採った。

### 参考

- `.coff/src/coff-issue-list.skill.md`：埋め込みコマンドと `allowed-tools` でプログラム化した既存例
- issue/2026/07/1921-gh-skill-installable.md：配布単位が skill ディレクトリであることの由来
