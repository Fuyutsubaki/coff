---
status: open
---
# skill をワークフロー部分と LLM 部分に分けるビルド工程 dullmify を coff-compile に加える

frontmatter で `coff-dullmify: true` を宣言した skill ソースを、coff-compile が決定論的な Perl プログラムと薄い SKILL.md に分けて出力する。
制御（対象の選定、繰り返し、分岐、書き出し）をプログラムに移し、LLM は問われた判断にだけ答える形にして、トークン消費と想定外の挙動を減らし、事前承認をプログラム呼び出しだけに絞る。
最初の適用先は coff-compile 自身とする。

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

1. **dullmify は coff-compile のビルド工程とし、太いソースを正本のまま残す。** `coff-dullmify: true` の skill だけを、制御を担う `scripts/<name>.pl` と LLM の判断基準を持つ `SKILL.md` に分け、両成果物と bundle を全検査後に公開する。
2. **workflow は逐次 Perl を journal から replay する。** `start` と `resume <run> <index>` のたびに先頭から実行し、effect の順序と入力ハッシュ、`.pl` と runtime の md5 を検証し、`status`、`cancel`、7 日を期限とする `gc` を持たせる。
3. **薄い skill には往復方法と LLM の判断基準だけを残す。** `allowed-tools` は `${CLAUDE_SKILL_DIR}` 配下の Perl 呼び出しだけとし、書き出しを Perl に寄せるが、列挙外ツールを禁止する機構は追加しない。
4. **`Coff::Workflow` は各 dullmify 成果物へ複製する。** `coff-bundle: [scripts]` は列挙したディレクトリを実体出力へ複製し、参照 stub は `scripts/` を持たず、配布ミラーは skill ディレクトリ単位で同期する。
5. **最初の適用先は coff-compile とする。** compile、coff-init、coff-review-diff-code の変換は別 issue とする。

却下した代替案:

- 常駐プロセスとの往復（バックグラウンド起動と名前付きパイプ、MCP サーバー、プログラムが `claude -p` を呼ぶ逆転）: Bash ツールが起動済みプロセスの stdin に書けない。MCP は skill ごとの登録が配布と合わず、逆転は会話文脈と権限を引き継げない。
- `context: fork` とツールを絞った agent で Write / Edit を外す: AskUserQuestion が使えず、承認を挟む skill が成立しない。

## 決めたこと

- 言語は一旦 Perl。Go は採らない（元は skill とプロセスが標準入出力で処理する想定だったが、それには生きているプロセスと会話する必要があり、skill はそれには不十分だった。その前提では Go はわざわざインストールを要求するほど便利ではなかった）
- dullmify は coff-compile の工程にする
- 権限は「プログラム呼び出しの事前承認と書き出しの移譲」まで。強制はしない
- 最初の適用先は coff-compile 自身

## 完了条件

- [x] `Coff::Workflow` が start / resume / status / cancel / gc、非決定の検出、バージョンの固定、同じ答えの再送への冪等を持ち、テストが通る
- [x] `coff-dullmify: true` のソースをビルドすると `SKILL.md` と `scripts/<name>.pl` がフッタ付きで出力され、`scripts/lib/Coff/Workflow.pm` が複製される
- [x] 生成した Perl が `perl -c` を通らないときは `failed` になり、SKILL.md と bundle を含む全出力先が変わらない
- [x] 薄い SKILL.md は frontmatter の `allowed-tools` がプログラム呼び出しだけで `coff-*` キーが残らず、本文に bash スニペットと選定・skip・書き出しの手順が無い
- [ ] coff-compile 自身が dullmify され、薄い成果物で `/compile --force coff-compile` を承認プロンプトなしで完走できる（lint 候補の提示、承認、英訳、書き出し、レポート）
- [x] 配布ミラー `skills/coff-compile/` に `scripts/` が含まれる

## 実装メモ

### 実装詳細

- `.coff/src/coff-compile/scripts/lib/Coff/Workflow.pm`：replay runtime と複数ファイルの原子的な公開を実装
- `.coff/src/coff-compile/t/workflow.t`：driver、非決定、バージョン固定、再送、公開失敗を検証
- `.coff/src/coff-compile.skill.md`：`coff-dullmify` と `coff-bundle` の生成規則を追加し、自身へ宣言
- `.coff/src/compile.skill.md`：配布ミラーを skill ディレクトリ単位の同期へ変更
- `.claude/skills/coff-compile/`：英訳した薄い skill、workflow、runtime をブートストラップ
- `skills/coff-compile/`：ブートストラップ成果物をディレクトリ単位で同期

後で効く制約:

- Perl は 5.30 以上の構文と core モジュールだけを使い、生成プログラムは `FindBin` から runtime を読む。
- 副作用は `step` に置き、時計と乱数を使わず、hash のキーを sort し、effect 呼び出しを `eval` で囲まない。
- 問いは `{"run":…,"index":…,"ask":{"topic":…,"kind":"llm"|"user","input":…}}`、終了は `{"run":…,"done":true,"report":…}` とする。
- `resume` の stdin は UTF-8 の文字列として保存し、JSON を要求する topic だけを生成プログラム側で decode する。
- lint 候補は `{start, end, replacement, label}` の JSON 配列とし、承認された索引だけをソースへ適用する。
- 既存の Perl、薄い skill 本文、英訳は別々の `llm` topic とし、`coff-translate: false` は薄い skill にも適用する。
- 全出力を出力先と同じディレクトリへ一時保存し、`perl -c` 後に rename する。失敗時は backup から既存出力を戻す。
- bundle は skip でも同期し、内容が同じファイルは書き換えない。参照出力は `scripts/` を持たない。
- journal は `.pl` のフッタ md5 と `Workflow.pm` の md5、effect の順序と入力ハッシュを持つ。
- `done` と `cancel` は journal を終端結果に置き換え、`status` は未回答の問い、`gc` は 7 日より古い run を扱う。

### 完了条件の確認手段

1. `prove -I .coff/src/coff-compile/scripts/lib .coff/src/coff-compile/t/`
2. `/compile --force coff-compile` の後、`ls .claude/skills/coff-compile/scripts/` に `coff-compile.pl` と `lib/Coff/Workflow.pm` があり、`tail -n1` で SKILL.md と `.pl` のフッタ md5 が `md5sum .coff/src/coff-compile.skill.md` と一致する
3. 書き出し関数をテストで叩く。SKILL.md、`.pl`、bundle の 3 出力先を渡し、`.pl` が壊れていれば失敗が返り、3 つとも作られず、既存があれば変わらないこと。1 のテストに含める
4. `head` で frontmatter を見る。本文は `grep -c '```' .claude/skills/coff-compile/SKILL.md` が 0 で、読んで選定・skip・書き出しの手順が無いこと
5. 初回は `.coff/src/coff-compile.skill.md` を直接読んで手順として実行し、成果物を作る（壊れたら `git restore .claude/skills/coff-compile`）。次に薄い成果物で `/compile --force coff-compile` を実行し、lint 候補の提示から `compiled` の報告までを一度通す。途中で Bash の承認プロンプトが出ないことを見る（出れば `allowed-tools` の前方一致が heredoc に効いていない）。Bash を広く許可したセッションや auto mode では判別できないので、通常の権限設定のセッションで行う
6. `diff -r .claude/skills/coff-compile skills/coff-compile`（compile のディレクトリ単位同期を先に入れておく）

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
