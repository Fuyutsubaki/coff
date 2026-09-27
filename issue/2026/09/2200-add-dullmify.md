---
status: open
---
# skill の制御を指定した言語のプログラムに移す skill dullmify を加える

dullmify は skill のソースを受け取り、指定した言語（まず Ruby と C++）のプログラムと、それを呼び出す薄い skill に変換する。
制御をプログラムに移し、制御の揺れ、トークン消費、エラーからの暴走を減らし、事前承認をプログラムの呼び出しに絞るためである。

## 目的

coff の skill は、手順の制御と LLM にしかできない判断（例: メール本文から地名を取り出して県名にする）を一つの Markdown に混ぜて書いており、制御まで LLM が読んで実行するので、手順を毎回読むトークンを消費し、解釈が実行ごとに揺れ、エラーが起きると手順にない対処を始め、ファイル操作やコマンド実行の事前承認を絞れない。
本 issue の目的は、制御をプログラムに移して LLM の役割を問われたことへの回答に限り、dullmify を coff-compile のコンパイル処理の一つにしつつ、coff に依らない汎用の skill にすることである。
生成したプログラムは skill の利用者のチームがレビューして受け入れるので、チームが読める言語で出力できることを要件に含める。

## 現状

- coff-compile（`.coff/src/coff-compile.skill.md`）はソース 1 つを Markdown 1 ファイルに出力し、skip 判定はそのフッタの md5 で行う。skill にファイルを同梱する仕組みはなく、issue/2026/09/2222-skill-source-dir.md が作る。coff-init（`.coff/src/coff-init.skill.md`）は、導入する coff skill を名前で列挙している。
- 制御を LLM が担う例が coff-compile 自身で、対象の選定から出力までを bash スニペット付きの手順で書いている。判断の要らない skill では、`.coff/src/coff-issue-list.skill.md` が埋め込みコマンドと `allowed-tools: Bash(awk *)` でプログラム化した前例になっている。

## 設計方針

1. 実行方式は再実行（replay）とする。薄い skill がプログラムを呼ぶたびに先頭から実行し、記録済みの問いと副作用には記録した結果を返し、未回答の問いに当たったら記録を残して問いを出力し、終わる。Claude Code と Codex はどちらもサンドボックス下では呼び出しの終了時に残ったプロセスを終了させるので、両方で動くのは短いコマンドとファイルだけである（調査記録 2、3）。
2. 外界とのやり取りは、すべてランタイムの補助関数を通す。補助関数が結果を自動で記録し、再実行では記録を返すので、生成コードは普通の逐次処理の見た目になる。レビューの規則は「補助関数を通さない入出力はバグ」一つで済み、dullmify は構文検査と禁止 API の走査を通ったコードだけを書き出す。
3. 言語ごとの一式（ランタイム、起動スクリプト、検査スクリプト、生成ガイド）を `langs/<lang>/` に同梱し、LLM が書くのは workflow 本体だけにする。言語の追加はディレクトリの追加で済む。C++ は起動スクリプトが初回にビルドし、`${TMPDIR:-/tmp}` にキャッシュする。
4. 薄い SKILL.md は言語に依らない定型にする。事前承認は起動スクリプトの呼び出しだけで、本文は「問いに答えて呼び直す、done なら報告する、failed なら止まる」を軸にし、問いに答える以外のことをさせない。failed のときに手順外の対処をさせないことで、エラーからの暴走を防ぐ。
5. coff とは frontmatter の `coff-dullmify: <lang>` でつなぐ。coff-compile は一時ディレクトリで `/coff-dullmify` を呼び、SKILL.md の英訳とフッタを施して公開する。coff-dullmify 自身は、ソースをディレクトリ（`.coff/src/coff-dullmify.skill/`）にして同梱ファイルを配る（issue/2026/09/2222-skill-source-dir.md が前提）。

- 切り離したプロセスを常駐させる案は採らない：サンドボックス下では両エージェントとも終了させられる。エージェント固有の手段（Claude Code の `run_in_background`、Codex の unified exec）なら生かせるが、薄い SKILL.md がエージェントごとに分かれる。
- 変数と実行位置を保存する案は採らない：C++ は呼び出しのスタックを保存できず、変数だけを保存すると「どこまで進んだか」で分岐する状態機械の形になり、レビューできるコードでなくなる。
- C++ のバイナリを同梱する案は採らない：配布は skill ディレクトリのコピーなので、ビルドした環境でしか動かない。
- 対象外：lint モード（issue/2026/09/2200-dullmify-lint-mode.md）、再生成の差分を小さくする仕組み、既存の coff skill への適用、Codex での事前承認（skill に仕組みがなく、利用者の rules ファイルが担う）、Claude Code と Codex 以外のエージェントと Windows、問いの文面の英訳、coff-dullmify 自身の dullmify。

## 決めたこと

- dullmify のオプションは入力ソース、出力先、言語、lint モードの指定とする。再生成の差分を小さくする仕組みは、いったん入れない
- 生成する言語はオプションで指定し（レビューをする際、チームで使っている言語が最も都合がよい）、対応できる言語だけに対応して（Node、Ruby、C++、Go、Python はそれぞれ事情が違い、簡単に実装できる気がしない）、まず C++ と Ruby を実装する。C++ は利用者の環境で、初回の実行時にビルドする
- プロセスは常駐させず、呼び出しのたびにプログラムを実行する。プログラムは LLM への問いが要る箇所で記録を残して問いを返し、skill は答えを渡して再実行する。これを終了まで繰り返す（別プロセスを立てて通信する形は skill としての頒布のコストが上がる。skill 内で実行したシェルは、終了するまで LLM と通信できないらしい）
- Codex でも動くことを要件にし、生成した skill と `/coff-dullmify` 自身の両方に求める
- coff-compile は dullmify を呼び出し、dullmify を coff のコンパイル処理の一つにする。coff-dullmify の同梱ファイルを配る仕組みは、別の issue（issue/2026/09/2222-skill-source-dir.md）で作る
- 初回実装（ブランチ `issue/dullmify-skill`）は真似も参考もしない（Perl で始めて途中で方針を変えたが、捨てるはずの Perl 時代の仕様があちこちに入り込み、蝕まれていた）
- 引数と答えは heredoc ではなく run ディレクトリのファイルで渡し、起動スクリプトのコマンドは `start`（run を作る）と `continue <run>`（書かれたファイルを取り込んで再実行する）の 2 つにする。薄い SKILL.md の事前承認は `Write` と起動スクリプトの 2 つになる（Claude Code の Bash ツールが `{`、引用符、`}` を含む heredoc を静的に拒否するため。調査記録 6 と 9。2026-09-27）

## 完了条件

- [ ] Ruby と C++ のランタイムが、問いの往復、副作用を一度だけ実行すること、非決定と workflow の変更の検出、呼び出しの誤りで run を残すこと、例外で failed にすることのテストを通る。検査スクリプトが、構文の誤りと禁止 API をそれぞれ検出するテストを通る
- [ ] `/coff-dullmify <source> -o <dir> --lang <ruby|cpp>` が、Claude Code と Codex のどちらでも、薄い SKILL.md と `scripts/` を書く。薄い SKILL.md は事前承認が `Write` と起動スクリプトの呼び出しだけで、本文が定型と一致する。生成コードが検査を通らなければ、失敗を報告して `<dir>` に何も残さない（LLM が書いた workflow の下書きは `assemble.sh` が消す）
- [ ] fixture から生成した skill が、Ruby と C++ のどちらでも、Claude Code では承認で止まらずに、Codex では `workspace-write` で最後まで動く
- [ ] `coff-dullmify: ruby` を宣言したソースを coff-compile でビルドすると、成果物に `scripts/` が入り、SKILL.md の description が英訳されてフッタが付く。ソースが変わらなければ skip される
- [ ] `/compile` で coff-dullmify が同梱ファイルごと `.claude/skills/coff-dullmify/` と配布ミラー `skills/coff-dullmify/` に入り、`gh skill install` で単独の skill として導入できる。coff-init が導入対象に含める

## 実装メモ

### 実装詳細

issue/2026/09/2222-skill-source-dir.md の実装を先に済ませる。本 issue がそちらに求めるのは、`SKILL.md` 以外の同梱ファイル（`.md` を含む）を英訳もコメント除去もせずにそのまま写すこと、成果物ディレクトリに同梱ファイル以外を足さないこと、ミラーを削除も含めてディレクトリごと同期すること、`*.skill/SKILL.md` の `coff-dist` を読むこと、ディレクトリのソースの skip 判定である。

- `.coff/src/coff-dullmify.skill/langs/ruby/runtime.rb`：Ruby のランタイム（CLI、run ディレクトリ、記録と再実行、補助関数）
- `.coff/src/coff-dullmify.skill/langs/ruby/run`：Ruby の起動スクリプト
- `.coff/src/coff-dullmify.skill/langs/ruby/check`：構文検査と禁止 API の走査
- `.coff/src/coff-dullmify.skill/langs/ruby/ext`：workflow ファイルの拡張子（`rb`）。`assemble.sh` が読む
- `.coff/src/coff-dullmify.skill/langs/ruby/GUIDE.md`：Ruby で workflow を書くときの API と規則
- `.coff/src/coff-dullmify.skill/langs/cpp/`：C++ の同じ 5 ファイル（`runtime.hpp`、`run`、`check`、`ext`、`GUIDE.md`）。`run` はビルドとキャッシュも担う
- `.coff/src/coff-dullmify.skill/assemble.sh`：`<outdir>` の組み立て（検査、薄い SKILL.md の生成、`scripts/` への複製）。事前承認の対象
- `.coff/src/coff-dullmify.skill/templates/thin-skill.md`：薄い SKILL.md の定型
- `.coff/src/coff-dullmify.skill/SKILL.md`：dullmify の太いソース（`coff-dist: true`）
- `.coff/test/coff-dullmify/`：ランタイム、検査、`assemble.sh` のテスト（言語ごとの手書きの workflow と、LLM 役を務める駆動スクリプト `run-tests.sh`）と、fixture の skill ソース
- `.coff/src/coff-compile.skill.md`：`coff-dullmify` 指示の処理
- `.coff/src/coff-init.skill.md`：導入対象に coff-dullmify を足す

呼び出しの規約:

- 起動は `sh <skill ディレクトリ>/scripts/run start` と `sh <skill ディレクトリ>/scripts/run continue <run>` の 2 つ。`start` は run ディレクトリを作って `{"run":"<run>","write":"<run>/args"}` を返すだけで、workflow は実行しない。LLM は skill の引数を `<run>/args` にファイルを書くツールで書き、`continue <run>` を呼ぶ。答えも同じく、問いが示す `<run>/answer.<n>` に書いて `continue <run>` を呼ぶ。ランタイムはファイルの末尾の改行を 1 つだけ除いて使い、取り込んだ答えのファイルは消す。`gh skill install` が実行権限を落とすので、`sh` を前に付けて呼ぶ（調査記録 4）。
- 出力は stdout に JSON 1 行。問いは `{"run":"<run>","ask":<n>,"prompt":"…","input":"…","write":"<run>/answer.<n>"}`、終了は `{"done":true,"report":"…"}`、失敗は `{"failed":"<理由>"}` とし、done と failed では run ディレクトリを消す。stdout はこの規約だけに使い、workflow は stdout にも stderr にも直接書かない。
- workflow の例外、非決定、C++ のビルドの失敗は、どれも stdout の `{"failed":…}` で返す。終了コード 2 を使うのは、呼び出しの誤りと、書くべきファイルがまだないときだけである。
- 呼び出しの誤り（`start` が作った目印のファイルがない run）と、`args` や未回答の問いの `answer.<n>` がまだないときは、記録に触れずに stderr と終了コード 2 で返し、run を残す。薄い SKILL.md は、stderr のとおりにしてから `continue` を呼び直すよう案内する。`continue` は記録の地点から再実行するので、答えを取り込んだ後に殺されても同じ呼び出しで再開できる（調査記録 9）。
- run ディレクトリは `${TMPDIR:-/tmp}` の下に作り、その絶対パスを毎回の出力で LLM に渡し直す。Claude Code のサンドボックス下では `/tmp` が読み取り専用で `$TMPDIR` が `/tmp/claude` になり、サンドボックスの有無で `$TMPDIR` の解決先が変わるので、呼び出しごとに解決し直さない（調査記録 2、4）。
- run の開始時の作業ディレクトリを記録し、再実行のたびにそこへ移ってから workflow を実行する。補助関数に渡す相対パスはこの作業ディレクトリが基準になるので、Claude Code と Codex で呼び出し時の作業ディレクトリが違っても結果は変わらない。

問いと答え:

- 答えは自由な文字列とする。形式を求める問いでは workflow が答えを検査し、壊れていたら理由を添えて問い直す（例外にして run を失わない）。問い直しの上限は workflow が決める。
- 副作用は workflow が補助関数で起こし、問いの文面で LLM にファイルの書き換えやコマンドの実行をさせない。ユーザーへの確認やファイルの参照など、答えるのにツールが要る問いは文面でそれを指示してよく、そのツールは通常の権限設定に従う。dullmify はユーザーへの確認を含むソースも変換する。

記録と再実行:

- 記録は 1 件ごとに種別、照合キー、結果を持つ。C++ でも JSON パーサなしで読める形式にする（JSON は LLM への出力だけに使う）。
- 未回答の問いも種別と照合キーを記録し、`answer` がその結果を埋める。再実行で記録の種別か照合キーが食い違ったとき、または記録を使い切らないうちに done か新しい問いに達したときは、非決定として failed にする。run の開始時に workflow のハッシュを記録し、途中で workflow が変わったら failed にする。
- 書き込みとコマンド実行は初回だけ実行し、再実行では記録を返す。読み込みも記録するので、workflow が自分で書き換えたファイルを再実行で読み直しても分岐は変わらない。
- 補助関数は次の集合とし、名前は言語の慣習に合わせてよい。環境変数や時刻が要るときは、コマンド実行で取る。
  - **引数**：stdin で受けた文字列をそのまま返す。分割は workflow が行う。
  - **問い**：`ask(prompt, input)` は答えの文字列を返す。照合キーは prompt と input のハッシュ。
  - **コマンド実行**：argv（シェルを通さない）と任意の stdin を受け、終了コード、stdout、stderr を返す。非 0 でも例外にしない。照合キーは argv と stdin。
  - **ファイル**：読み込み（内容か、存在しないこと）と書き込み（親ディレクトリも作る）。照合キーはパスで、書き込みは内容のハッシュも含める。
  - **失敗**：`fail(reason)` で workflow を止め、failed にする。
- report は workflow 本体の戻り値の文字列とする。
- 未回答の問いで workflow を抜ける合図は、生成コードの例外処理に捕まらない形にする。Ruby では `StandardError` を継承しない例外、C++ では `std::exception` を継承しない型にする。合図を投げた後の補助関数の呼び出し（Ruby の `ensure` や C++ のデストラクタから呼ばれるもの）は、ランタイムが何もせずに空の結果を返す。投げ直さないのは、C++ で巻き戻し中のデストラクタから例外を投げると `std::terminate` になるためである。

検査:

- `check <workflow ファイル>` は構文検査と禁止 API の走査を行い、どちらかが失敗すれば非 0 で終わる。Ruby は `ruby -c`、C++ はランタイムと同じ `${CXX:-c++} -std=c++17 -fsyntax-only` を使う。
- 禁止 API の走査は、`check` に書いた正規表現の拒否リストで機械的に行う。対象は、補助関数を通さない外界との入出力（stdout と stderr への直接の出力を含む）、時刻と乱数、動的な呼び出し（Ruby の `eval`、`send`、`const_get`、`instance_eval` など）、合図を捕まえる例外処理（`rescue Exception`、`catch (...)`）、プロセスの終了（Ruby の `exit`、`abort`、`at_exit`、C++ の `exit(`、`abort(`、`atexit(`）、ランタイム以外の読み込み（Ruby の `require` も含む。`set` などはランタイムが読み込んでおく）である。C++ の `#include` は許可リスト（入出力を伴わない標準ヘッダとランタイム）で検査する。標準ヘッダは C の入出力関数を推移的に読み込むので、C と POSIX の関数（`system(`、`popen(`、`fopen(`、`open(`、`write(`、`printf(`、`getenv(`、`time(`、`rand(` など）の呼び出しも拒否リストに入れる。
- 走査はコメントと文字列リテラルを除いてから行う。Ruby は標準ライブラリの Ripper で字句に分けてコメントと文字列の中身を除き、式展開（`#{…}`）の中は走査する。C++ はコメントと文字列リテラルを除いてから走査し、除く処理を単純に保つため raw 文字列リテラルは `check` が拒否する。
- dullmify は生成と検査を 3 回まで繰り返し、通らなければ何も書かずに失敗を報告する。別の手段でコンパイラを呼ぶなどして、検査を回避してはいけない。

言語の前提:

- Ruby は 3.0 以上の標準ライブラリだけ、C++ は C++17 と POSIX だけを使い、外部ライブラリは使わない。C++ のコンパイラは `${CXX:-c++}` にする。
- C++ のキャッシュのキーは `workflow.cpp` と `runtime.hpp` の内容から POSIX の `cksum` で作る（macOS にもある）。ビルドは一時ファイルに書いて rename で置く。

薄い SKILL.md:

- 定型には HTML コメントを書かない。本文が定型と一致するとは、frontmatter を閉じる `---` の次の行から末尾まで（coff-compile の成果物ではフッタの行を除く）が、定型とバイト単位で一致することを指す。
- 定型のファイル名を `SKILL.md` にしない。`gh skill install` は入れ子の `SKILL.md` を別の skill として列挙し、インストール時に frontmatter を注入する（調査記録 4）。
- frontmatter はソースのものから `allowed-tools` を除いて写し、`allowed-tools: Write Bash(sh ${CLAUDE_SKILL_DIR}/scripts/run *)` を加える。`coff-*` キーの除去は coff-compile が行い、dullmify は coff を知らない。
- 起動スクリプトは絶対パスで、単独のコマンドとして呼ばせる。`cd … &&` やパイプを付けると `allowed-tools` の規則に一致しない。呼び出しの合間には、問いに答える以外の操作をさせない。done では `report` をそのまま表示し、何も付け足さない。
- 本文は英語の定型にする。起動スクリプトは「この SKILL.md と同じディレクトリの `scripts/run`」と書き、`${CLAUDE_SKILL_DIR}` を使わない（Codex には同じ変数がなく、相対パスを SKILL.md のディレクトリ基準で解決する。調査記録 3、4）。
- 本文に `$ARGUMENTS` を書かず、「この skill に与えられた引数を `<run>/args` にそのまま書く」と指示する。Codex は `$ARGUMENTS` を展開しないので、書けば文字どおり渡ってしまう。Claude Code は、プレースホルダがなければ本文の末尾に `ARGUMENTS: <入力>` を付け足す（調査記録 1）。
- 呼び出しが終わらないうちに制御が戻ったとき（Claude Code は 2 分の既定のタイムアウトでバックグラウンドに移す）は、終わるまで待って最後の出力を読み、出力がなければ `continue` を呼び直すよう案内する。Codex での待ち方は調べていないので、案内はエージェントを名指ししない書き方にする。

dullmify:

- 引数は `<source> -o <outdir> --lang <lang>` で、どれも必須にし、frontmatter の `description` にこの呼び出し方を書く。対応外の言語は、生成の前に `langs/<lang>/GUIDE.md` の有無で確かめ、対応する言語（`langs/` の下のディレクトリ）を示してエラーにする。`assemble.sh` も対応外の言語を拒む。lint のオプションは issue/2026/09/2200-dullmify-lint-mode.md で足す。
- 太いソースは言語に依らない規則（工程ごとのコメント、検査の回数、検査を回避しないこと）だけを持ち、言語ごとの API と禁止 API は `langs/<lang>/GUIDE.md` と `check` に置いて、GUIDE を読ませる。
- coff-dullmify 自身も Claude Code と Codex の両方で動くよう、本文では同梱ファイルを SKILL.md のディレクトリ基準の相対パスで指す。`allowed-tools` で事前承認するのは `Write` と `sh ${CLAUDE_SKILL_DIR}/assemble.sh *` にし、`assemble.sh` は絶対パスの単独のコマンドとして呼ばせる。（当初は `assemble.sh` だけの予定だったが、調査記録 6 により workflow をファイルで渡す形に変えた。2026-09-25）
- LLM が書くのは workflow 本体だけで、`<outdir>/scripts/workflow.<ext>` にファイルを書くツールで書き、そのパスを `assemble.sh <lang> <source> <outdir> <workflow ファイル>` に渡す。`<outdir>/SKILL.md` と `<outdir>/scripts/` は `assemble.sh` のもので、検査に通らなければ理由を出し、`scripts/` を消して非 0 で終わる。通れば `<outdir>/SKILL.md` と `<outdir>/scripts/` を消してから、ソースの frontmatter と定型から作った薄い SKILL.md と、`scripts/`（`run`、ランタイム、`workflow.*`）を書く。`<outdir>` のほかのファイルには触れない。
- 生成コードには、ソースの工程（番号付きの手順の 1 項目。手順がなければ段落）ごとに、節の見出しと工程の番号をソースの言語でコメントする。同梱ファイル（ランタイム、起動スクリプト、検査スクリプト、ガイド、定型）はコンパイルされずにそのまま配られるので、英語で書く。
- fixture は `.coff/test/coff-dullmify/fixtures/prefecture.skill.md` とし、複数の問い、問いを含むループ、辞書による分岐、コマンド実行、ファイルの書き込みを通り、中身の決まった report を返すものにする。description は日本語で書く（確認手段 4 で英訳を確かめる）。同じディレクトリに、skill の引数 `prefecture.input` と、期待する report `prefecture.expected`（1 行）を置く。LLM の答えが揺れても report が変わらないよう、答えの紛れない入力を使い、report の 1 行の形式をソースに文字どおり書く。
- テストと確認の出力は、リポジトリの外（`mktemp -d`）に置く。`gh skill` はリポジトリ内の入れ子の `skills/<name>/SKILL.md` も skill として見つけうる。

coff-compile:

- `coff-dullmify: <lang>` のソースでは、coff-compile の Lint（§2）を行わない。「生成物から消しても実行 LLM が手順を完遂できるか」という基準は、実行時にソースを読まない dullmify の成果物には当たらない。
- coff-compile は、ラッパー compile が `/coff-compile` を呼ぶのと同じく、`.claude/skills/coff-dullmify/SKILL.md` を読んでその手順を実行する形で `/coff-dullmify <src> -o <一時ディレクトリ> --lang <lang>` を呼ぶ。`--out` があっても、読むのはこの場所である。その後、SKILL.md の `description` だけを英訳して（`coff-translate: false` なら訳さない）フッタを付け、成果物ディレクトリと入れ替える。本文の英訳とコメント除去（§5 の a、b）は行わない。dullmify が失敗したとき、または `.claude/skills/coff-dullmify/SKILL.md` がないときは `failed: <理由>` を報告し、成果物に触れない。
- coff-dullmify のランタイムだけを直したとき、dullmify 済みの skill は md5 が変わらないので `--force` で作り直す。workflow も生成し直される（受容）。
- 参照 stub（`--ref`、`--agent codex`）は、これまでどおり SKILL.md の stub だけを置く。
- ビルドは 2 段になる。coff-compile の新しい成果物を先に作ってから、coff-dullmify をビルドする。新しく作った skill が同じセッションで見えなければ、セッションを始め直す。

### 完了条件の確認手段

1. `sh .coff/test/coff-dullmify/run-tests.sh` が終了コード 0 で終わる。駆動スクリプトは LLM 役として決まった答えを送り、各項目を出力の JSON と run ディレクトリの中身で判定する。非決定は、テスト用の workflow でわざと補助関数を迂回して起こす。検査スクリプトは、言語ごとに、構文の誤りを含む workflow、拒否リストの分類ごとに禁止 API を 1 つずつ呼ぶ workflow、正しい手書きの workflow を用意し、前の 2 つで非 0、最後で 0 になることを確かめる。あわせて、コメントと文字列の中の禁止 API の字面が通ること、Ruby の式展開の中の禁止 API が止まること、C++ の raw 文字列リテラルと許可リスト外の `#include` が止まることを確かめる。
2. 確認手段 5 のビルドの後に行う。言語ごとに `mktemp -d` で空の一時ディレクトリを作り、`claude -p --permission-mode default "/coff-dullmify <fixture の絶対パス> -o <一時ディレクトリ> --lang ruby"`（と `cpp`）を実行する。`<一時ディレクトリ>/SKILL.md` の `allowed-tools` が起動スクリプトの規則 1 行だけであることと、本文が `templates/thin-skill.md` と一致することを確かめる。検査の失敗は、別の空の一時ディレクトリに向けて `CXX=false` を設定した同じコマンドで `--lang cpp` を変換し、失敗が報告され、そのディレクトリが空のままであることで確かめる。Codex では、使い捨ての git リポジトリへ `gh skill install --from-local <coff のリポジトリ> coff-dullmify --agent codex` で coff-dullmify を入れ、`codex exec -s workspace-write "Use the skill coff-dullmify with arguments: <fixture の絶対パス> -o <一時ディレクトリ> --lang ruby"`（と `cpp`）で変換し、`allowed-tools` と本文について同じ確認を行う（`CXX=false` の確認は Claude Code だけで行う）。
3. 2 で Claude Code が変換した出力を、言語ごとに使い捨ての git リポジトリの `.claude/skills/prefecture/` に置き、`claude -p --permission-mode default --output-format json "/prefecture <prefecture.input の内容>"` の結果で、`permission_denials` に `scripts/run` の呼び出しがないことと、最後の応答に `prefecture.expected` の 1 行が含まれることを確かめる。同じ出力を `.agents/skills/prefecture/` に置き、`codex exec -s workspace-write "Use the skill prefecture with arguments: <prefecture.input の内容>"` の最後の応答にも同じ 1 行が含まれることを確かめる。
4. 確認手段 5 のビルドの後、新しいセッションの対話で行う。fixture の写しに `coff-dullmify: ruby` を足して一時的に `.coff/src/prefecture.skill.md` に置き、`/coff-compile --out <一時ディレクトリ> prefecture` の後に `<一時ディレクトリ>/skills/prefecture/` の `scripts/` と SKILL.md（英訳された description、フッタ、`coff-*` キーがないこと、本文が `templates/thin-skill.md` と一致すること）を確かめる。同じコマンドをもう一度実行して何も報告されない（skip）ことを確かめてから、写しを消す。
5. `/compile --force coff-dullmify` を実行し、`diff -r -x SKILL.md .coff/src/coff-dullmify.skill .claude/skills/coff-dullmify` と `diff -r .claude/skills/coff-dullmify skills/coff-dullmify` がどちらも空であることを確かめる。`gh skill install --from-local . coff-dullmify --agent claude-code --dir <一時ディレクトリ>` で導入できることと、`gh skill install --from-local . --agent claude-code --dir <一時ディレクトリ> </dev/null` の一覧に coff-dullmify の下の別 skill が出ないことを確かめる。`grep -n coff-dullmify .coff/src/coff-init.skill.md .claude/skills/coff-init/SKILL.md` で導入対象に入っていることを確かめる。

### 調査記録

1. Claude Code の skill の仕様（https://code.claude.com/docs/en/skills 、2026-09-22 確認）: 「Claude Code substitutes `${CLAUDE_SKILL_DIR}` and `${CLAUDE_PROJECT_DIR}` in two places: the skill's markdown content, and Bash rules in the `allowed-tools` frontmatter」（v2.1.196 以上）。`allowed-tools` は事前承認だけで、他のツールを制限しない。`$ARGUMENTS` は入力した文字列のまま展開され、本文にプレースホルダがなければ末尾に `ARGUMENTS: <入力>` が付け足される。
2. Claude Code のプロセスの扱い（code.claude.com/docs の tools-reference、interactive-mode、sandboxing、settings-reference と、anthropic-experimental/sandbox-runtime @ ddbeb74（v0.0.77）。2026-09-22 確認）:
   - サンドボックスがないとき、呼び出しの後に残ったプロセスの扱いは文書にない。Bash のタイムアウトは既定 2 分、最大 10 分で、タイムアウトした呼び出しはバックグラウンドに移る。`run_in_background` の呼び出しは応答の後も動き続ける。
   - Linux のサンドボックスは bubblewrap を `--unshare-pid`、`--die-with-parent`、`--new-session` で起動する（`linux-sandbox-utils.ts`）。コマンドが終わると PID 名前空間ごと中のプロセスが終了させられ、`test/sandbox/pid-namespace-isolation.test.ts` がこの挙動を確かめている。
   - 同じく Linux では `/tmp` が読み取り専用で、`$TMPDIR` は `/tmp/claude` に書き込める。ホストのディレクトリなので呼び出しをまたいで残る。サンドボックスの有無で `$TMPDIR` の解決先が変わる（sandboxing.md）。
   - macOS（Seatbelt）で残ったプロセスがどうなるかは文書にない。
3. Codex のプロセスと skill の扱い（openai/codex @ fe6455a の codex-rs、2026-09-21 時点）:
   - Linux の `read-only` と `workspace-write` は bubblewrap を `--unshare-pid` 付きで使い（`linux-sandbox/src/bwrap.rs`）、コマンドの終了とともに中のプロセスが終了させられる。サンドボックスがなくても、素の `&` はプロセスグループごと SIGKILL される（`core/src/unified_exec/process.rs` の Drop）。
   - プロセスを生かしてやり取りする正規の手段は unified exec（`exec_command` と `write_stdin`、既定で有効）である。
   - `workspace-write` では `/tmp` と `$TMPDIR` に書き込め、呼び出しをまたいで残る（`protocol/src/protocol.rs`）。
   - skill に `${CLAUDE_SKILL_DIR}` にあたる変数はなく、相対パスは SKILL.md のディレクトリ基準で LLM が解決する（`ext/skills/src/catalog_prompt.rs`）。`allowed-tools` もなく、事前承認は rules ファイル（`.codex/rules/` の `prefix_rule`）で行う。
4. 試作（2026-09-22、scratchpad の使い捨て skill、WSL2）:
   - Claude Code 2.1.278 の `claude -p --permission-mode default` で、`allowed-tools: Bash(sh ${CLAUDE_SKILL_DIR}/scripts/run *)` は `sh <絶対パス>/scripts/run start <<'DULLMIFY_EOF' … DULLMIFY_EOF` を承認なしで通した。`allowed-tools` を外すと承認待ちで止まった。
   - codex-cli 0.155.1 の `codex exec -s workspace-write` は、SKILL.md に書いた `scripts/run` を SKILL.md のディレクトリ基準で解決して実行した。どちらでも heredoc は引用符と `$HOME` を展開せずに渡し、`$TMPDIR` は未設定だった（Claude Code はサンドボックスなし）。
   - Codex の `workspace-write` では、`nohup … &` と `setsid nohup … &` のどちらで切り離したプロセスも、次の呼び出しまでに消えていた。Claude Code（サンドボックスなし）では残り、ファイル越しに 2 往復して完走した。
   - gh 2.95.0 の `gh skill install --from-local` は、`scripts/run` の実行権限を落とした。skill の中に入れ子の `templates/SKILL.md` があると、それを別の skill（`t/templates`）として列挙し、インストール時に `metadata.local-path` の frontmatter を注入した。別名の `templates/thin-skill.md` はそのまま残った。
5. この環境には ruby 3.0.2 と g++ 11.4 があり、bubblewrap と socat がないので、Claude Code のサンドボックスは試せない。サンドボックス下の動作は調査記録 2 の仕様で判断した。
6. 実装時の確認（2026-09-25、Claude Code 2.1.281、codex-cli 0.155.1）: Claude Code の Bash ツールは、`{`、引用符、`}` をこの順で含むコマンド文字列を「Contains brace with quote character (expansion obfuscation)」として実行前に拒否する。引用符付き heredoc の本文も対象で、`dangerouslyDisableSandbox` でも通らない。C++ の関数本体は必ずこれに当たり、Ruby もハッシュリテラルに文字列があれば当たる。heredoc で `assemble.sh` に渡す当初の設計は Claude Code で C++ を一度も assemble できなかったので、workflow をファイルに書いてパスを渡す形に変えた。`claude -p --permission-mode default` では、skill の `allowed-tools` に `Write` を書くと、作業ディレクトリの外（`/tmp` の下）への Write も承認なしで通る。`Edit(**)` は作業ディレクトリの下だけ、`Edit(${CLAUDE_SKILL_DIR}/…)` は置換されず通らない。Codex は heredoc でもファイルでも通る。
7. 同じ確認で、薄い SKILL.md の frontmatter の `description` に `` `---` `` を含む fixture では、Claude Code が `allowed-tools` の起動スクリプトの呼び出しを承認しなかった。`---` を含まない description に変えると通った。値の中の `---` を閉じ区切りと誤読して後続のキーが落ちるとみられる。fixture の description を「ハイフン 3 つだけの行」に言い換え、coff-dullmify の `<source>` の説明に、frontmatter の値に `---` を含めないと書いた。

8. 確認手段の実行（2026-09-25〜26）: 1 は `run-tests.sh` が全件通過。2 は Claude Code（`claude -p --permission-mode default`）と Codex（`codex exec -s workspace-write`）の両方で Ruby と C++ の変換が通り、`allowed-tools` が起動スクリプトの 1 行だけで本文が定型と一致した。`CXX=false` では 3 回とも拒否され、出力ディレクトリは空のままだった。3 は両言語・両エージェントで `permission_denials` なし（Claude Code）に完走し、最後の応答に `prefecture.expected` の 1 行が含まれた。4 は `--out` の一時ディレクトリに `scripts/` と英訳された description、フッタ付きの SKILL.md ができ、2 回目は skip になった。5 は bundle とミラーの `diff -r` が空、`gh skill install --from-local` で導入でき、一覧に入れ子の skill は出ず、coff-init に coff-dullmify がある。レビュー後の修正と `start` / `continue` への規約変更（2026-09-27）の後、1、2、3、5 を再実行した。2 は Claude Code で両言語とも承認なしで通り、3 は両言語・両エージェントで完走して期待の 1 行を返し、run ディレクトリは残らなかった。4 は再実行していない（coff-compile 側の手順は変えていない）。

9. 答えを取り込んだ直後に殺される場合（2026-09-27）: 旧規約の `answer <run> <n>` は答えを記録してから workflow を再実行するので、再実行中のコマンド（ビルドやテスト）がエージェントのコマンドタイムアウトを超えて殺されると（Codex はプロセスグループごと SIGKILL、Claude Code のサンドボックスは呼び出し終了時に PID 名前空間ごと終了。調査記録 2、3）、答えは記録済みなのに完走していない run が残り、同じ答えの再送は exit 2、`start` は全部を聞き直しになる。`continue` は記録の地点から再実行するので、この状態から続けられる。Ruby のランタイムは SIGTERM を失敗として扱わず素通しにする（`rescue Exception` で捕まえると run を消してしまう）。テスト `slow.rb` / `slow.cpp` で、`timeout` で殺した後の `continue` が次の問いに進むことを確かめる。

### 参考

- `.coff/src/coff-issue-list.skill.md`：埋め込みコマンドと `allowed-tools` でプログラム化した既存例
- issue/2026/09/2222-skill-source-dir.md：ソースのディレクトリ化と同梱（本 issue の前提）
- issue/2026/09/2200-dullmify-lint-mode.md：dullmify の lint モード
