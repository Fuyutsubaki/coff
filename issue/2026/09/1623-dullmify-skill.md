---
status: open
---
# skill をワークフロー部分と LLM 部分に分ける skill dullmify を、生成する言語を指定できる形で作り直す

`/coff-dullmify` が skill ソースを、決定論的なプログラムの workflow と薄い SKILL.md に分けて出力する。制御をプログラムに移し、LLM は問われた判断にだけ答える形にして、トークン消費と想定外の挙動を減らし、事前承認をプログラム呼び出しだけに絞る。
Perl 固定の初回実装は一度完成させたが、「チームで使っている言語でないと生成物をレビューできない」という指摘を受けて破棄した。生成する言語を指定できるようにするには事実上の作り直しになるので、本 issue を open に戻し、言語の指定から設計し直す。

## 目的

coff の skill は、手順の制御と LLM にしかできない判断（文の要否の判定、翻訳、ユーザーへの問い）を一つの Markdown に混ぜて書いている。
制御まで LLM が読んで実行するため、手順の記述が毎回トークンを消費し、ファイル操作を LLM が行うので事前承認を絞れず、手順が長いほど読み飛ばしや順序違いが起きる。
本 issue の目的は、宣言した skill について制御の主体をプログラムに移し、LLM の役割を判断への回答に限ることである。LLM から Write / Edit を強制的に取り上げることは扱わない。
生成したプログラムは skill の利用者がレビューして受け入れるものなので、利用者のチームが読める言語で出力できることを要件に加える。

## 現状

- coff-compile は `.coff/src/*.skill.md` を `.claude/skills/<name>/SKILL.md` に出力する。成果物は Markdown だけで、コードを含める機構はない。ビルド指示は frontmatter の `coff-*` で宣言し、skip 判定は出力先の最終行のフッタの md5 で行う。
- LLM が bash スニペットを読んで制御を担っているソースは coff-compile、compile、coff-init、coff-review-diff-code の 4 つ。coff-issue-list は awk の埋め込みコマンドと `allowed-tools` で既にプログラム化されている。
- Claude Code の `allowed-tools` は skill のターンで列挙したツールを事前承認する機構で、列挙外を制限しない。`${CLAUDE_SKILL_DIR}` で skill ディレクトリ基準のパスを書ける。Bash ツールは起動済みプロセスの stdin に書けない（調査記録 1）。
- 配布の単位は skill ディレクトリで、`gh skill install` はサブディレクトリごとコピーする。ラッパー compile のミラー同期は SKILL.md 単体の複製で、issue/2026/08/0501-coff-include-directive.md（skill 同梱のビルド指示。未着手）がディレクトリ単位への拡張を予定している。
- Perl 固定の初回実装（runtime、雛形、自己ホストした coff-dullmify、coff-compile の dullmify 段と `coff-bundle`、ミラーのディレクトリ単位の同期）はブランチ `issue/dullmify-skill`（PR #24、マージせず close）に残っている。master には何も入っていない。

## 設計方針

言語の指定が未決なので、ここには初回実装から引き継ぐ方針だけを書く。言語に関わる設計は未決を解いてから足す。

1. `coff-dullmify` は独立 skill とし、ソースと出力先を引数で受けて一時出力する。md5、フッタ、英訳、最終出力は扱わず、coff-compile が staging 越しに呼んで公開する。
2. `.coff/src/coff-dullmify.skill.md` は手順と判断基準を持つ太いソースとする。全 skill で同じになる部分（runtime、プログラムの土台、SKILL.md の定型）は手書きの雛形を複製し、LLM が作るのは workflow 本体と topic 節だけにする。
3. 実行は replay 方式とする。workflow を毎回先頭から実行し、記録済みの effect は保存した値を返す。effect は LLM への問いと副作用の 2 種類だけで、`start` / `resume` の往復で進む。
4. 薄い skill の事前承認は workflow の呼び出しだけにする。

生成規則を coff-compile に埋める案、dullmify のソースを薄くする案、dullmify が最終位置へ直接書く案は採らない。共通部分の重複、ソースの位置付け、責務の混在を避ける。常駐プロセスとの往復（名前付きパイプ、MCP、`claude -p` の逆転）は Bash ツールが起動済みプロセスの stdin に書けず、`context: fork` でツールを絞る案は AskUserQuestion が使えないので採らない。

## 決めたこと

- 生成するプログラムの言語は、skill に指定できるようにする。チームで使っている言語でないと生成物をレビューできない、という指摘を受けた（2026-09-21）
- Perl 固定の初回実装は破棄する。言語の指定は事実上の作り直しになるため。参照用にブランチ `issue/dullmify-skill` は残す
- dullmify は独立した skill にし、その上で coff-compile の選択肢にする
- 全 skill で同じになる部分は毎回 LLM で作らず、あらかじめ作った雛形を差し込む（初回実装の最初の生成コードがあまりにも読みづらかった）
- coff-compile から dullmify へは skill の呼び出しで行う。プログラム同士の依存は作らない
- coff-dullmify のインターフェースは clang などの現実のコンパイラに寄せる。ソースと出力先を指定し、既定は持たない
- md5 系は runtime に持たせず、coff-compile でカバーする
- dullmify は一時ディレクトリに書き、それを coff-compile に弄らせる（dullmify は複雑かつ汎用的なのでシンプルにしたい）
- `.coff/src/coff-dullmify.skill.md` はソースファイルに当たる概念なので、プログラムの実行から始まる薄い形ではなく太いソースとして書く
- 手書きと生成のコードにはコメントを書く
- driver は持たない。雛形の頭と尻を差し込み、workflow のファイル 1 本を実行ファイルにする
- 削った機能が無いことを確かめるテストは持たない
- coff-compile 自身はまだ dullmify しない
- 権限は「プログラム呼び出しの事前承認と書き出しの移譲」まで。強制はしない
- runtime と雛形は汎用ライブラリなので、常に品質と安定を優先する（coff では起きないことを理由に見送らない）
- 初回実装での言語の判断（上の決定で覆した）: 一旦 Perl。Go は採らない（元は skill とプロセスが標準入出力で処理する想定だったが、それには生きているプロセスと会話する必要があり、skill はそれには不十分だった。その前提では Go はわざわざインストールを要求するほど便利ではなかった）

## 未決

- 言語をどこで指定するか。ソースの frontmatter、リポジトリ単位の設定、`/coff-dullmify` の引数のどれか、またはその組み合わせ
- 最初に対応する言語。初回実装の Perl を選択肢の一つとして残すか
- runtime の持ち方。言語ごとに runtime と雛形を実装して同梱するか、journal を扱う部分を言語に依らない単体のコマンドに寄せて、生成コードを薄くするか。前者は言語の数だけ replay の実装とテストが要る
- 実行環境の前提。Perl は OS 同梱なので導入が要らなかった。Go を見送った理由（インストールを要求するほどではない）が、他の言語にもそのまま当たるか
- 構文検査の門（初回実装の `perl -c`）を言語ごとにどう持つか

## 完了条件

言語の指定のしかたが決まったら polish で書き直す。以下は Perl 固定の初回実装の条件で、言語に依らない部分の目安として残す。

- [ ] `Coff::Workflow` が `llm` / `step`、`die` による中断、実行順の journal と非決定の検出、値の切り離し、`start` / `resume` だけを持ち、テストが通る
- [ ] `/coff-dullmify .coff/src/coff-compile.skill.md -o <dir>` が 3 ファイルを書き、workflow.pl の頭と尻、runtime、SKILL.md の定型は同梱の雛形とバイト一致する。`<dir>/scripts/workflow.pl` があれば `workflow` の問いに `existing` として渡る
- [ ] `workflow` の答えが `perl -c` を通らないときは `failed` になり、`<dir>` に書かれない
- [ ] `.coff/src/coff-dullmify.skill.md` が太いソースで、その `workflow.pl` は `/compile` で自分から生成される
- [ ] coff-compile が `coff-dullmify: true` のソースで一時ディレクトリに前の `workflow.pl` を置き、`/coff-dullmify` の後に SKILL.md を英訳し、SKILL.md と workflow.pl にフッタを付けて公開する
- [ ] 薄い SKILL.md は `allowed-tools` が `workflow.pl` の呼び出しだけで `coff-*` キーが残らず、本文に bash スニペットと制御の手順が無い
- [ ] 手書きの Perl（runtime、雛形）と生成した workflow.pl に意図のコメントがある
- [ ] `/compile --force coff-dullmify` が、coff-dullmify の薄い成果物の呼び出しで承認プロンプトを出さずに完走できる
- [ ] 配布ミラー `skills/coff-compile/` と `skills/coff-dullmify/` が正本とディレクトリ単位で一致する

## 実装メモ

### 実装詳細

作り直しの設計が決まってから書く。初回実装の構成はブランチ `issue/dullmify-skill` で読める。

- `.coff/src/coff-dullmify/scripts/lib/Coff/Workflow.pm`：replay の runtime（約 240 行。先頭に仕組みとレビューの仕方の README）
- `.coff/src/coff-dullmify/templates/`：workflow の頭と尻、薄い SKILL.md の定型
- `.coff/src/coff-dullmify/t/`：runtime と組み立てのテスト（96 件）
- `.coff/src/coff-dullmify.skill.md`、`.coff/src/coff-compile.skill.md`、`.coff/src/compile.skill.md`：太いソース、dullmify 段と `coff-bundle`、ミラーのディレクトリ単位の同期

初回実装で分かった制約（Perl の語で書いてあるが、多くは言語に依らない）:

- Perl は 5.30 以上の構文と core モジュールだけ。生成する `workflow.pl` は `use utf8` を宣言する（非 ASCII の文字列リテラルが JSON 出力で二重にエンコードされる）。`use` 群、`FindBin`、`run_workflow` は雛形の頭と尻にあり、生成しない。既存 workflow を LLM に渡すときはフッタと雛形の頭と尻を除く。
- 副作用は `step` に置き、時計と乱数を使わず、hash のキーを sort する。effect を `eval {}` で囲まない（中断の例外が握りつぶされる）。
- 問いは `{"run":…,"index":…,"ask":{"topic":…,"input":…}}`、終了は `{"run":…,"done":true,"report":…}`、失敗は `{"run":…,"done":true,"failed":"<理由>"}`。
- `resume` の stdin と `start` の引数は runtime が UTF-8 の文字列に戻して保存し、workflow には文字列で渡す。JSON を要求する topic だけを workflow 側で decode する。パスをファイル操作に渡すときは workflow 側で `Encode::encode_utf8` する。
- run を消すのは workflow 自身の done と failed だけ。呼び出しの誤りは journal を書く前に stderr へ返し、run を残す。薄い SKILL.md の定型は「JSON でない応答は呼び出しの誤りなので同じ run に再送する」と案内する。
- journal に入れる値と workflow に返す値は JSON の往復で切り離す（同じ参照を共有すると workflow 側の書き換えが記録に混ざり、replay が非決定として止まる）。run のディレクトリは done と failed で消す。
- coff-compile は `/coff-dullmify <source> -o <staging>` を実行し、staging の 3 ファイルを読んで英訳とフッタを施し公開する。`perl -c` は coff-dullmify が通しているので coff-compile では再検査しない。
- `step` の識別は実行順だけで、同じ位置の step の中身が変わっても検出しない（ソースが変われば md5 で workflow.pl ごと再生成されるので受容）。3 ファイルの書き出しはファイルごとの temp + rename で、途中で失敗すると先行ファイルだけが更新される（多ファイルのトランザクションを落とした帰結として受容）。
- 薄い SKILL.md はソースの frontmatter から `coff-*` と `allowed-tools` を落とし、`allowed-tools: Bash(perl ${CLAUDE_SKILL_DIR}/scripts/workflow.pl *)` を加える。
- `perl -c` の門には runtime の `lib` を `-I` で渡す（一時ファイルの場所では雛形の `use lib` が runtime を見つけられない。prove の PERL5LIB が孫プロセスまで継承されると欠落を隠すので、テストは起動時に PERL5LIB を消す）。
- 生成した workflow.pl は実行時に同梱の `templates/` と `scripts/lib/` を読む。`coff-bundle` の同期は skip でも行い、dullmify が staging に書いた `Workflow.pm` より後に複製して同梱の runtime を正とする。
- run の状態は `${XDG_STATE_HOME:-$HOME/.local/state}/coff/<name>/<run>/journal.json` に置く。skip 判定は SKILL.md と workflow.pl の両方のフッタで行い、workflow.pl のフッタは `# <!--…-->` の行コメントにする。

### 完了条件の確認手段

言語の指定が決まったら書き直す。初回実装の確認手段はブランチの同じファイルにある。

### 調査記録

1. Claude Code docs（https://code.claude.com/docs/en/skills.md 、同 tools.md。2026-09-17 確認）: `allowed-tools` は skill のターンの事前承認で、列挙外のツールは通常の権限設定のまま使える。指定子は settings の permissions と同じ（`Bash(git add *)` 形）。`${CLAUDE_SKILL_DIR}` は skill ディレクトリに展開され、スクリプトは `scripts/` に置くのが慣習。`context: fork` と `agent` で subagent 実行にできる。Bash ツールはバックグラウンドプロセスに EOF を渡し、後から stdin に書く手段はない。
2. 依頼者の事前検討（2026-09-16）の要点:
   - 状態の置き場は「LLM 側」でも「VM のスタック保存」でもなく、プログラム側のファイル。再開に要るのは命令位置ではなく「どの工程にいて、どの値を持つか」なので、LLM 待ちの位置だけを停止点にすれば足りる。
   - 明示的な状態機械（`pc` と switch）は生成コードが読めなくなる。逐次コードを毎回先頭から実行し、記録済みの effect は結果を返すだけにする replay 方式（Temporal / DBOS / Restate 型）なら、`if` / `for` / `while` がそのままワークフロー記述になる。
   - Perl での実現: `llm` は journal に答えがなければ `die` で workflow 全体から脱出する（例外を継続の代用にする）。effect の識別は実行順で足り、ループの反復番号も生成コードに出ない。再生時に順序と入力ハッシュを照合し、食い違えば非決定として止める。文脈は `local` の動的スコープで渡し、深い関数からも引数なしで届く。`step (&)` の prototype でブロック構文にできる。
   - 採らない Perl の手段: source filter（文字列の書き換えで corner case を背負う）、`Keyword::Simple` / `XS::Parse::Keyword`（experimental、XS 依存は配布と逆方向）、Coro（最終リリース 2020 年）、`Future::AsyncAwait`（同一プロセス内の中断にしか効かず、プロセスをまたぐなら結局 replay が要る）。
   - runtime に最低限持たせる 3 点: 再開の検証（run と effect の索引、現在の工程を照合し、LLM に次の工程を指定させない）、重複への対処（同じ答えの再送で二重に進めない。外部への書き込みは冪等にする）、バージョンの固定（開始時の workflow を特定し、更新後の別コードで古い状態を再開しない）。
   - プロセスの終了と workflow の終了を分ける。前者で一時領域を消さない。後者は done / failed / cancelled の終端処理として記録し、`cancel` と `gc` を持つ。
   - 上の 3 点のうち再送の冪等とバージョンの固定、および `cancel` と `gc` は、実装が膨らんだため初回実装では採らなかった（決めたこと参照）。
   - Claude Code の Dynamic workflows（Workflow ツール）は近いが、スクリプト自身がファイル操作とシェル実行をできず、外部操作を agent に戻す設計なので採らない。
   - 配布は Perl 同梱の Linux / macOS を前提にし、PAR::Packer による単体実行ファイル化は採らない。
3. 試作（2026-09-17、scratchpad、約 40 行の Perl 5.34）: `die` による中断、journal への保存、`resume` での答えの差し込み、journal のキー改変による非決定の検出が成立した。
4. 先行例: SkillSmith（skill を deterministic / LLM / reference に分解して DAG に落とす。ループは DAG に持たず agent に戻す）と Rote（trevhud/rote。SKILL.md → pipeline.yaml → 実行基盤向けコード）。どちらも「LLM を要する箇所で親の Claude に戻し、同じ workflow を再開する」実行モデルは持たない。SkillSmith の「すべての skill を workflow にせず、曖昧なら元 skill に fallback する」分類は、宣言のないソースを従来どおりビルドする形で採った。
5. 初回実装のレビューで分かったこと（2026-09-20〜21）:
   - 生成物のレビューには、言語が読めることに加えて replay の仕組み（`die` で抜けて先頭から再実行する、実行順で照合する）の理解が要る。runtime の先頭に置いた README は 3 回書き直し、3 行の workflow で `start` と `resume` の動きを見せる形に落ち着いた。
   - 生成コードの大半は定型の補助関数（UTF-8 の読み書き、一時ファイルからの置き換え、コマンドの実行）だった。外部ライブラリを許せば縮むが、配布の単位が skill ディレクトリなので、利用者に導入を求めるか skill ごとに同梱するかになり釣り合わない。定型を runtime 側に一度だけ書いて export すれば、依存なしで同じ効果が得られる。
   - 多観点レビューで直した点: 呼び出しの誤りで run を消さない、引数と答えを境界で UTF-8 に戻す、答えの検査を問いの直後に置く、同梱ディレクトリの同期を skip でも行う。作り直しでも同じ要件になる。

### 参考

- `.coff/src/coff-issue-list.skill.md`：埋め込みコマンドと `allowed-tools` でプログラム化した既存例
- issue/2026/07/1921-gh-skill-installable.md：配布単位が skill ディレクトリであることの由来
