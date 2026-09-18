---
status: open
---
# skill をワークフロー部分と LLM 部分に分ける skill dullmify を作り、coff-compile から呼べるようにする

`/coff-dullmify <source>.skill.md -o <dir>` が skill ソースを、決定論的な Perl の workflow と薄い SKILL.md に分けて出力する。LLM が作るのは workflow 本体と topic 節だけで、runtime と driver と定型は雛形を複製する。
制御をプログラムに移し、LLM は問われた判断にだけ答える形にして、トークン消費と想定外の挙動を減らし、事前承認をプログラム呼び出しだけに絞る。
coff-compile は `coff-dullmify: true` のソースで一時ディレクトリに `/coff-dullmify` を書かせ、英訳とフッタを施して公開する。最初の適用先は coff-compile と coff-dullmify 自身。

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

1. `coff-dullmify` は独立 skill とし、`<source>.skill.md -o <dir>` から4ファイルを一時出力する。既存 workflow は `workflow` の問いへ全文を渡し、md5、フッタ、英訳、最終出力は扱わない。
2. `.coff/src/coff-dullmify.skill.md` は手順と判断基準を持つ太いソースとする。runtime、19行の driver、SKILL.md の定型だけを手書きし、workflow.pl はソースから生成する。
3. runtime は `llm(topic, input)`、`step { ... }`、`die`、実行順の journal、非決定の検出、JSON による値の切り離し、`start` / `resume` だけを持つ。done と failed で run を削除する。
4. coff-compile は staging に既存 workflow を置き、topic `dullmify` で一時出力を書かせる。SKILL.md の英訳とコメント除去、SKILL.md と workflow.pl のフッタ、md5 と skip、実体出力への書き出しは coff-compile が担う。
5. 薄い skill の `allowed-tools` は `Bash(perl ${CLAUDE_SKILL_DIR}/scripts/run.pl *)` だけとする。runtime と driver は節ごと、生成 workflow は補助関数ごとに日本語のコメントを書く。

生成規則を coff-compile に埋める案、dullmify のソースを薄くする案、dullmify が最終位置へ直接書く案は採らない。共通部分の重複、ソースの位置付け、責務の混在を避ける。

## 決めたこと

- 言語は一旦 Perl。Go は採らない（元は skill とプロセスが標準入出力で処理する想定だったが、それには生きているプロセスと会話する必要があり、skill はそれには不十分だった。その前提では Go はわざわざインストールを要求するほど便利ではなかった）
- dullmify は独立した skill にし、その上で coff-compile の選択肢にする
- 全 skill で同じになる部分は毎回 LLM で作らず、あらかじめ作った雛形を差し込む（初回実装の生成コードがあまりにも読みづらい）
- coff-compile から dullmify へは LLM 経由（topic `dullmify` で `/coff-dullmify` を実行）で呼ぶ。Perl 同士の依存は作らない
- coff-dullmify のインターフェースは clang などの現実のコンパイラに寄せる。ソースと出力先を指定し、既定は持たない
- md5 系は runtime から捨て、coff-compile でカバーする
- dullmify は一時ディレクトリに書き、それを coff-compile に弄らせる（dullmify は複雑かつ汎用的なのでシンプルにしたい）
- `.coff/src/coff-dullmify.skill.md` はソースファイルに当たる概念なので、Perl の実行から始まる薄い形ではなく太いソースとして書く
- Perl にはコメントを書く
- driver（`run.pl`）は持たない。雛形の頭（use 群と runtime の読み込み）と尻（`run_workflow` の呼び出し）を差し込み、`workflow.pl` 1 本を実行ファイルにする
- 削った機能が無いことを確かめるテストは持たない
- 権限は「プログラム呼び出しの事前承認と書き出しの移譲」まで。強制はしない

## 完了条件

- [x] `Coff::Workflow` が `llm` / `step`、`die` による中断、実行順の journal と非決定の検出、値の切り離し、`start` / `resume` だけを持ち、テストが通る
- [x] `/coff-dullmify .coff/src/coff-compile.skill.md -o <dir>` が 4 ファイルを書き、`run.pl`、runtime、SKILL.md の定型は同梱の雛形とバイト一致する。`<dir>/scripts/workflow.pl` があれば `workflow` の問いに `existing` として渡る
- [x] `workflow` の答えが `perl -c` を通らないときは `failed` になり、`<dir>` に書かれない
- [x] `.coff/src/coff-dullmify.skill.md` が太いソースで、その `workflow.pl` は `/compile` で自分から生成される
- [x] coff-compile が `coff-dullmify: true` のソースで一時ディレクトリに前の `workflow.pl` を置き、topic `dullmify` の後に SKILL.md を英訳し、SKILL.md と workflow.pl にフッタを付けて公開する
- [x] 薄い SKILL.md は `allowed-tools` が `run.pl` の呼び出しだけで `coff-*` キーが残らず、本文に bash スニペットと制御の手順が無い
- [x] 手書きの Perl（runtime、driver）と生成した workflow.pl に意図のコメントがある
- [ ] 薄い成果物で `/compile --force coff-compile` と `/compile --force coff-dullmify` を承認プロンプトなしで完走できる
- [x] 配布ミラー `skills/coff-compile/` と `skills/coff-dullmify/` が正本とディレクトリ単位で一致する

## 実装メモ

### 実装詳細

- `.coff/src/coff-dullmify/scripts/lib/Coff/Workflow.pm`：2 effect と replay に絞った runtime。各関数に意図のコメント
- `.coff/src/coff-dullmify/scripts/run.pl`：同じディレクトリの workflow.pl を読む19行の driver
- `.coff/src/coff-dullmify/templates/`：start / resume だけを案内する薄い SKILL.md の定型
- `.coff/src/coff-dullmify/t/`：runtime、既存 workflow の受け渡し、雛形の一致、`perl -c` の門を検証
- `.coff/src/coff-dullmify.skill.md`：手順、`workflow` / `topics` の判断基準、組み立て規則を持つ太いソース
- `.coff/src/coff-dullmify/scripts/dullmify.pl`：削除。生成した workflow.pl が処理を担う
- `.coff/src/coff-compile.skill.md`：staging、topic `dullmify`、英訳、フッタ、ファイル単位の公開を定義
- `.claude/skills/coff-compile/`、`.claude/skills/coff-dullmify/`：ブートストラップで生成した英語の薄い skill、workflow、driver、runtime
- `skills/coff-compile/`、`skills/coff-dullmify/`：正本とディレクトリ単位で一致する配布ミラー

後で効く制約:

- Perl は 5.30 以上の構文と core モジュールだけ。生成する `workflow.pl` は `use utf8` を宣言する（非 ASCII の文字列リテラルが JSON 出力で二重にエンコードされる）。`use` 群、`FindBin`、`run_workflow` は `run.pl` にあり、生成しない。
- 副作用は `step` に置き、時計と乱数を使わず、hash のキーを sort する。effect を `eval {}` で囲まない（中断の例外が握りつぶされる）。
- 問いは `{"run":…,"index":…,"ask":{"topic":…,"input":…}}`、終了は `{"run":…,"done":true,"report":…}`、失敗は `{"run":…,"done":true,"failed":"<理由>"}`。
- `resume` の stdin は UTF-8 の文字列として保存し、JSON を要求する topic だけを workflow 側で decode する。
- journal に入れる値と workflow に返す値は JSON の往復で切り離す（同じ参照を共有すると workflow 側の書き換えが記録に混ざり、replay が非決定として止まる）。run のディレクトリは done と failed で消す。
- topic `dullmify` の入力は `{source, out}`、答えは `ok` か失敗の理由。一時ディレクトリの中身を LLM に運ばない。
- lint 候補は `{start, end, replacement, label}` の JSON 配列とし、承認された索引だけをソースへ適用する。
- 薄い SKILL.md はソースの frontmatter から `coff-*` と `allowed-tools` を落とし、`allowed-tools: Bash(perl ${CLAUDE_SKILL_DIR}/scripts/run.pl *)` を加える。

### 完了条件の確認手段

1. `prove -I .coff/src/coff-dullmify/scripts/lib .coff/src/coff-dullmify/t/`
2. 一時 dir に古い `scripts/workflow.pl` を置いて `/coff-dullmify .coff/src/coff-compile.skill.md -o <一時dir>` を実行し、最初の問いの `existing` にそれが入ること、完走後に `ls` で 4 ファイル、`cmp` で `run.pl` と `Workflow.pm`、`diff` で SKILL.md の定型段落を確かめる
3. 組み立てをテストで叩く（壊れた workflow 本文で失敗が返り、`<dir>` に何も書かれないこと）。1 に含める
4. `head -12 .coff/src/coff-dullmify.skill.md` に手順が書かれていること。`/compile --force coff-dullmify` を通し、`.claude/skills/coff-dullmify/scripts/workflow.pl` のフッタ md5 がソースと一致すること
5. 8 の実行中に topic `dullmify` の問いの後に `translate` が続き、完走後に `tail -n1` で両フッタの md5 が `md5sum` と一致すること
6. `head` で frontmatter を見る。`grep -c '```'` が 0 で、読んで制御の手順が無いこと
7. `grep -c '^\s*#' ` で各 Perl のコメント行を数え、`sub` ごとに一言以上あることを読んで確かめる
8. 初回は `.coff/src/coff-dullmify.skill.md` を直接読んで手順として実行し、次に `.coff/src/coff-compile.skill.md` で同じことをして成果物を作る（壊れたら `git restore`）。その後、薄い成果物で `/compile --force coff-compile` と `/compile --force coff-dullmify` を通す。Bash の承認プロンプトが出ないことを見る（auto mode では判別できないので通常の権限設定のセッションで行う）
9. `diff -r .claude/skills/coff-compile skills/coff-compile` と `diff -r .claude/skills/coff-dullmify skills/coff-dullmify`

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
