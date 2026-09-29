---
status: done
---
# skill の制御を指定した言語のプログラムに移す skill dullmify を加える

dullmify は skill のソースを受け取り、指定した言語（まず Ruby と C++）のプログラムと、それを呼び出す薄い skill に変換する。
制御をプログラムに移し、制御の揺れ、トークン消費、エラーからの暴走を減らし、事前承認をプログラムの呼び出しとファイルの書き込みに絞るためである。

## 目的

coff の skill は、手順の制御と LLM にしかできない判断（例: メール本文から地名を取り出して県名にする）を一つの Markdown に混ぜて書いており、制御まで LLM が読んで実行するので、手順を毎回読むトークンを消費し、解釈が実行ごとに揺れ、エラーが起きると手順にない対処を始め、ファイル操作やコマンド実行の事前承認を絞れない。
本 issue の目的は、制御をプログラムに移して LLM の役割を問われたことへの回答に限り、dullmify を coff-compile のコンパイル処理の一つにしつつ、coff に依らない汎用の skill にすることである。
生成したプログラムは skill の利用者のチームがレビューして受け入れるので、チームが読める言語で出力できることを要件に含める。再生成のたびにプログラム全体を読み直す前提で、差分を小さくする仕組みは持たない。

## 現状

- coff-compile（`.coff/src/coff-compile.skill.md`）はソース 1 つを Markdown 1 ファイルに出力し、skip 判定はそのフッタの md5 で行う。ディレクトリのソースは同梱ファイルを成果物に写す（issue/2026/09/2222-skill-source-dir.md）。coff-init（`.coff/src/coff-init.skill.md`）は、導入する coff skill を名前で列挙している。

## 設計方針

1. 実行方式は再実行（replay）とする。薄い skill が `continue` を呼ぶたびにプログラムを先頭から実行し、記録済みの問いと副作用には記録した結果を返し、未回答の問いに当たったら記録を残して問いを出力し、終わる。Claude Code と Codex はどちらもサンドボックス下では呼び出しの終了時に残ったプロセスを終了させるので、両方で動くのは短いコマンドとファイルだけである（調査記録 2、3）。引数と答えは run ディレクトリのファイルで渡す（調査記録 6）。
2. 補助関数は React の hooks にならう。workflow は「引数と記録」から決まる純粋な関数（render）とし、不純なものは `once`（観測。`useMemo` にあたる）と `effect`（世界を変える操作。`useEffect` にあたる）のブロックの中にだけ置く。どちらもブロックは初回だけ実行し、再実行では記録を返す（`effect` は実行の前に記録を予約する）。`ask` は Suspense の `use` と同じく中断して答えを待つ。時刻、乱数、環境変数、ファイル、コマンドは、この 2 つの上に作った便利関数で扱う。規則の中心は「不純なものは once と effect の中だけ」になる。生成コードには、レビューのためにソースの工程ごとのコメントを付ける。
3. dullmify は、構文検査と、会話を継承しない新しいサブエージェントの点検を通らなければ、書き出したものを残さない。点検は規則違反とソースの手順の写しの両方を見て、どちらの指摘でも不合格にして直させる。写しは正規表現では確かめられないので、規則違反も含めて LLM に読ませる。
4. 言語ごとの一式（ランタイム、ランタイムの起動、構文検査、生成ガイド）を `langs/<lang>/` に、言語に依らない起動スクリプトを 1 つ同梱し、LLM が書くのは workflow 本体だけにする。ランタイムは既存のライブラリを使い、C++ は nlohmann/json を同梱してファイル操作を `<filesystem>` で行う。C++ はランタイムの起動がバイナリのないときにビルドしてキャッシュする。
5. 薄い SKILL.md は言語に依らない短い定型にする。事前承認は起動スクリプトの呼び出しと `Write` だけで、問いに答える以外のことをさせず、failed では手順外の対処をさせない。同梱ファイルは日本語で書く。coff とは frontmatter の `coff-dullmify: <lang>` でつなぐ。coff-compile は lint をかけずに一時ディレクトリで `/coff-dullmify` を呼び、`description` の英訳とフッタを施して公開する。

- 採らない案：入出力の種類ごとに記録と再生を持つ固定の補助関数（コマンド、読み込み、書き込み）だけを用意すること（それ以外の時刻や乱数を外部コマンドで取ることになり、観測と副作用の区別もない）、切り離したプロセスの常駐（サンドボックス下で終了させられる）、変数と実行位置の保存（C++ はスタックを保存できず、状態機械の形になる）、C++ のバイナリの同梱（ビルドした環境でしか動かない）、同じエージェントの自己点検（書いた本人の見落としが点検でも重なる）、dullmify の点検をスクリプトから `claude -p` や `codex exec` で起動すること（どちらのエージェントかの判定と、入れ子の起動の承認が要る）。
- 対象外：lint モード（issue/2026/09/2200-dullmify-lint-mode.md）、既存の coff skill への適用、Codex での事前承認、Claude Code と Codex 以外のエージェントと Windows、問いの文面の英訳、coff-dullmify 自身の dullmify。

## 決めたこと

- プロセスは常駐させず、呼び出しのたびにプログラムを実行する。LLM への問いが要る箇所で記録を残して問いを返し、skill は答えを渡して再実行する（別プロセスを立てて通信する形は頒布のコストが上がる。skill 内で実行したシェルは、終了するまで LLM と通信できないらしい）
- 引数と答えは run ディレクトリのファイルで渡し、起動スクリプトのコマンドは `start` と `continue <run>` の 2 つにする
- dullmify のオプションは入力ソース、出力先、言語とし、生成する言語を指定させる（レビューをする際、チームで使っている言語が最も都合がよい）
- まず C++ と Ruby を実装し、C++ は利用者の環境で初回の実行時にビルドする
- Codex でも動くことを要件にし、生成した skill と `/coff-dullmify` 自身の両方に求める
- coff-compile は dullmify を呼び出し、dullmify を coff のコンパイル処理の一つにする。coff-dullmify の同梱ファイルが変われば、dullmify したソースは自動で作り直す（`--force` での作り直しはヒューマンエラーの温床になる）
- ライブラリを使う。C++ のランタイムは nlohmann/json を同梱し、POSIX は標準に代わりのないプロセス起動と一時ファイルだけに使う。ランタイムの単体テストを C++ は doctest、Ruby は minitest で書く
- 構文検査はコンパイラと `ruby -c` で行い、正規表現の拒否リストは使わず、新しいサブエージェントに点検させる。規則違反と手順の写しの両方を点検し、どちらの指摘でも不合格にして直させる
- 同梱ファイル（ランタイム、スクリプト、GUIDE、薄い SKILL.md の定型、点検の指示）のコメント、メッセージ、本文は日本語で書く
- 補助関数の基本は `arguments`、`ask`、`once`、`effect`、`fail` とし、時刻、乱数、環境変数、ファイル、コマンドは `once` と `effect` の上の便利関数にする
- `effect` は途中で殺されたら次の再実行で failed にする
- done を出す前にもう一度先頭から再実行し、同じ report になることを確かめる（React の StrictMode にあたる）
- 起動スクリプトは言語に依らず 1 つにし、言語ごとの違いはランタイムの起動だけにする（同じ規約を言語ごとに手で揃え続けない）
- `<outdir>` は dullmify 専用とし、存在しないか空のディレクトリを指定させる。3 回とも通らなければ `<outdir>` ごと片付ける
- `continue` で `args` がなければ、終了コード 2 で止める（`start` の出力を出し直しても、薄い SKILL.md にそれを受ける手順がない）

## 完了条件

- [x] Ruby と C++ のランタイムが、問いの往復、`once` と `effect` を一度だけ実行すること、非決定と workflow の変更の検出、`effect` の途中で殺された run を failed にすること、done の前の確認の再実行で非決定を検出すること、`args` がなければ終了コード 2 で止まること、`answer` が未作成なら同じ問いを出し直すこと、例外で failed にすること、問いの後で殺されても `continue` で続きから進むことのテストを通る。単体テストが、記録の読み書き、再実行の照合、初回と再実行で値の型がそろうこと、不正な UTF-8 を含む出力が正しい JSON になることを確かめる。構文検査が構文の誤りを検出する
- [x] 点検の指示が、規則違反の workflow（`once` や `effect` の外の不純、`once` の中で世界を変える操作を含む）と手順を誤って写した workflow をそれぞれ不合格にし、正しい workflow を合格にする
- [x] `/coff-dullmify <source> -o <outdir> --lang <ruby|cpp>` が、Claude Code と Codex のどちらでも、新しいサブエージェントで点検して薄い SKILL.md と `scripts/` を書き、Claude Code では承認で止まらない。薄い SKILL.md は事前承認が `Write` と起動スクリプトの呼び出しだけで、本文が定型と一致する。workflow にはソースの工程ごとのコメントが付く。3 回で通らなければ失敗を報告し、`<outdir>` を残さない
- [x] fixture から生成した skill が、Ruby と C++ のどちらでも、Claude Code では承認で止まらずに、Codex では `workspace-write` で最後まで動く。workflow が failed で終わると、Claude Code はそれを報告して止まる
- [x] `coff-dullmify: ruby` を宣言したソースを coff-compile でビルドすると、成果物に `scripts/` が入り、description が英訳されてフッタが付く。ソースも coff-dullmify も変わらなければ skip され、coff-dullmify の同梱ファイルだけが変わると作り直される
- [x] `/compile` で coff-dullmify が同梱ファイルごと `.claude/skills/coff-dullmify/` と `skills/coff-dullmify/` に入り、`gh skill install` で導入できる。coff-init が導入対象に含める。同梱ファイルが日本語で書かれ（nlohmann/json のファイルを除く）、そのライセンス全文を同梱する

## 実装メモ

### 実装詳細

- `.coff/src/coff-dullmify.skill/langs/ruby/runtime.rb`：Ruby のランタイム（CLI、run ディレクトリ、記録と再実行、補助関数）
- `.coff/src/coff-dullmify.skill/langs/ruby/launch`：Ruby のランタイムの起動。共通の `run` が照合を済ませてから呼ぶ
- `.coff/src/coff-dullmify.skill/langs/ruby/check`：構文検査（`ruby -c`）。`assemble.sh` が呼ぶ
- `.coff/src/coff-dullmify.skill/langs/ruby/GUIDE.md`：Ruby で workflow を書くときの API、規則、workflow のファイル名。点検の規則違反の基準も兼ねる
- `.coff/src/coff-dullmify.skill/langs/cpp/`：C++ の同じ 4 ファイル（`runtime.hpp`、`launch`、`check`、`GUIDE.md`）と、nlohmann/json v3.12.0 のリリースの `json.hpp` とライセンス全文（`LICENSE.MIT`）。`launch` はビルドとキャッシュも担う
- `.coff/src/coff-dullmify.skill/review.md`：点検の指示（言語に依らない観点、返す形式、サブエージェントへのプロンプトの雛形）
- `.coff/src/coff-dullmify.skill/assemble.sh`：`<outdir>` の組み立て（構文検査、薄い SKILL.md の生成、`scripts/` への複製）と、`--discard` での `<outdir>` ごとの片付け。どちらも `<outdir>` に `SKILL.md` と `scripts/` 以外があれば終了コード 2 で止まり、何も消さない。事前承認の対象
- `.coff/src/coff-dullmify.skill/templates/thin-skill.md`：薄い SKILL.md の定型
- `.coff/src/coff-dullmify.skill/templates/run`：言語に依らない起動スクリプト。`assemble.sh` が `scripts/run` に写す
- `.coff/src/coff-dullmify.skill/SKILL.md`：dullmify の太いソース（`coff-dist: true`）
- `.coff/test/coff-dullmify/`：ランタイムと構文検査のテスト（`workflows/<lang>/` の手書きの workflow と、LLM 役を務める駆動スクリプト `run-tests.sh`。`langs/<lang>/` の一式を `mktemp -d` に写して動かす）、ランタイムの単体テスト（`unit/cpp/` は同梱の doctest、`unit/ruby/` は minitest）、点検のテスト（`review/<lang>/` の、ソースどおりの `good` と、それに欠陥を 1 つだけ入れた `bad_*` の workflow と、`review-tests.sh`）、fixture の skill ソース
- `.coff/src/coff-compile.skill.md`：「dullmify ビルド」の節とその案内

呼び出しの規約:

- 起動は `sh <skill ディレクトリ>/scripts/run start` と `sh <skill ディレクトリ>/scripts/run continue <run>` の 2 つ。`start` は起動スクリプトだけで run ディレクトリを作って `{"run":"<run>","write":"<run>/args"}` を返し、workflow の実行もビルドもしない。C++ の `launch` は、バイナリがなければビルドする。キャッシュは呼び出しごとに解決した `${TMPDIR:-/tmp}` の下の、利用者ごとのディレクトリ `coff-dullmify-<uid>` に置く（skill ディレクトリには書かない）。自分が所有しシンボリックリンクでなければ権限を 700 に直して使い、他人のものなら終了コード 2 にする（古い版が残したディレクトリでも止まらないように）、解決先が変わればビルドし直す。LLM は skill の引数を `<run>/args` にファイルを書くツールで書き、`continue <run>` を呼ぶ。答えも同じく `<run>/answer` に書いて `continue <run>` を呼ぶ。ランタイムはファイルの末尾の改行を 1 つだけ除いて使い、取り込んだ `answer` は記録に書いた直後、再実行の前に消す（`args` は run が終わるまで残し、毎回読む）。`gh skill install` が実行権限を落とすので、`sh` を前に付けて呼ぶ（調査記録 4）。
- `continue` は毎回先頭から再実行して記録を消費するので、答えを取り込んだ後に殺されても同じ呼び出しで続きから進む（調査記録 8）。
- 出力は stdout に JSON 1 行で、終了コードは 0。問いは `{"run":"<run>","prompt":"…","input":"…","write":"<run>/answer"}`（`input` は問いの対象で、`prompt` はそれについて何をどう答えるか）、終了は `{"done":true,"report":"…"}`、失敗は `{"failed":"<理由>"}` とし、done と failed では run ディレクトリを消す。workflow の例外、非決定も `{"failed":…}` で返す。答えのファイルがまだないときは記録に触れずに再実行して、同じ問いを出し直す。未回答の問いがないのに `answer` があれば、消して無視する。`continue` は、目印の確認、`args` の確認、キーの照合、`launch` の呼び出し（C++ はビルドを含む）の順に行う。作業ディレクトリは `start` で起動スクリプトが記録する。stdout はこの規約だけに使い、workflow は stdout にも stderr にも直接書かない（ランタイムでは強制せず、GUIDE の規則と点検で止める）。
- 出力する文字列の不正な UTF-8 は U+FFFD に置き換え、出力を常に正しい JSON にする（nlohmann/json の `dump` は既定では例外を投げるので `error_handler_t::replace` を使う。Ruby は `scrub`）。置き換えは、記録するとき（照合キー、結果、取り込んだ答え）と出力するときだけで行い、便利関数の中では行わない。Ruby は文字列の操作が不正な UTF-8 で例外になるので、`arguments` の値も置き換える。
- C++ のビルドの失敗は、固定の文言の `{"failed":…}` を出し、コンパイラの出力は stderr にそのまま流す。このとき run を消す。コンパイラのフラグ（`-std=c++17` と `-I`）は `run` と `check` で同じものを使う。
- 終了コード 2 は、`start` が作った空の目印のファイル `<run>/.dullmify-run` がない run と、`args` がない run と、起動スクリプトが run やビルドの作業場所を用意できないときだけに使い、stderr に理由を書く。
- run ディレクトリは `${TMPDIR:-/tmp}` の下に作り、その絶対パスを `start` と問いの出力で LLM に渡し直す。サンドボックスの有無で `$TMPDIR` の解決先が変わるので、呼び出しごとに解決し直さない（調査記録 2、4）。
- run の開始時の作業ディレクトリを記録し、再実行のたびにそこへ移ってから workflow を実行する。補助関数に渡す相対パスはこの作業ディレクトリが基準になる。

問いと答え:

- 答えは自由な文字列とする。形式を求める問いでは workflow が答えを検査し、壊れていたら理由を添えて問い直す（例外にして run を失わない）。問い直しの上限は workflow が決める。
- 副作用は workflow が補助関数で起こし、問いの文面で LLM にファイルの書き換えやコマンドの実行をさせない。ユーザーへの確認やファイルの参照など、答えるのにツールが要る問いは文面でそれを指示してよく、そのツールは通常の権限設定に従う。

記録と再実行:

- 記録は JSON Lines（1 行 1 件）で、1 件ごとに種別、照合キー、結果を持つ。C++ は nlohmann/json、Ruby は標準の json で読み書きする。記録は先頭から順に消費して照合し、キーの一意は求めない。種別は `ask`、`once`、`effect` の 3 つ。照合キーはハッシュにせず値そのもの（問いは prompt と input、`once` と `effect` は呼び出し側が渡した JSON にできるキー。便利関数は種類名と引数をキーにする）を記録し、一致で比べる。
- 未回答の問いも種別と照合キーを記録し、`continue` が `<run>/answer` の内容でその結果を埋める。再実行で記録の種別か照合キーが食い違ったとき、または記録を残したまま done に達したときは、非決定として failed にする。
- 起動スクリプトは `scripts/` の全ファイルの名前と内容を名前順につないで POSIX の `cksum` でキーを作り、`start` で `<run>/workflow-key` に書く（キーが置き場所に依らないようにする）。`continue` では起動スクリプト自身が照合し、食い違えば run を消して固定の文言の failed を出す（ランタイムにはキーを渡さない）。キーは `launch` に渡し、C++ ではビルドのキャッシュのキーも兼ねる。ビルドは一時ファイルに書いて rename で置く。
- `once` はブロックを初回だけ実行し、結果を記録して返す。`effect` は、実行の前に結果のない記録を追記して保存し、実行の後に結果を埋める。再実行で結果のない `effect` に当たったら、副作用の途中で中断されたとして failed にする（起きたかどうか分からない副作用を黙って二度行わない）。どちらも初回の結果を JSON に通してから返し、初回と再実行で値の型をそろえる。結果は JSON にできる値に限る。記録に書く文字列も、不正な UTF-8 は U+FFFD に置き換える。ブロックが例外を投げたら、run を failed にして消す（workflow の rescue に捕まらない合図で抜ける）。ブロックの中で `fail` 以外の補助関数を呼ぶこと（入れ子）は禁じ、呼ばれたら failed にする。記録は `result` キーの有無で完了と未完了を区別し、`null` の結果も `"result": null` で持つ。照合キーも JSON に通して正規化する（Ruby の Symbol が初回と再実行で食い違わないように）。便利関数のキーは `["<種類名>", 引数…]` の配列とする。読み込みも `once` で記録する（読んだ後で自分が書いたファイルを、再実行では書く前の状態として読み直せるように）。記録が読めないときは failed にして run を消す。外から殺されたとき（SIGTERM など）は失敗として扱わず、run を残す。
- 補助関数は次の集合とし、名前は言語の慣習に合わせてよい。
  - **基本**：`arguments`（`<run>/args` の末尾の改行を 1 つ除いた内容を返す。分割は workflow が行う）、`ask(prompt, input)`（答えの文字列）、`once(key) { … }`（観測）、`effect(key) { … }`（世界を変える操作）、`fail(reason)`。
  - **便利関数**（`once` と `effect` で数行で書けるもの）：`now`（ISO 8601 の UTC、マイクロ秒までの文字列）、`random(n)`（n バイトの乱数の 16 進文字列）、`env(name)`（ないときは Ruby は `nil`、C++ は `std::nullopt`）、`read(path)`（ないときは同じく `nil` / `std::nullopt`）は `once`、`write(path, content)`（親ディレクトリも作り、値を返さない）と `command(argv, stdin = "")`（シェルを通さず、Ruby は文字列キーのハッシュ `{"exit_code", "stdout", "stderr"}`、C++ は構造体で返す。非 0 でも例外にせず、起動できなければ終了コード 127 と理由の stderr）は `effect` で作る。`ask` の `input` は省略でき、既定は空文字列。C++ の補助関数はすべて名前空間 `dullmify` に置く（`<unistd.h>` の `read`、`write` などとぶつけない）。`write` のキーには内容を含め、時刻の捕まえ損ねを非決定として検出する。
  - C++ の `once` と `effect` は、戻り値が nlohmann/json と往復できる型に限るテンプレートにする（合わない型はコンパイルで弾かれる）。`command` の fork と exec はランタイムが持つ（C++ に標準のプロセス起動がないため）。
- `fail` も、未回答の問いの合図と同じく workflow の例外処理に捕まらない形で抜ける。Ruby は `Dullmify.fail` とし、`Kernel#fail` は上書きしない。workflow の例外は、Ruby は `SignalException` を除くすべて、C++ は `catch (...)` まで含めて failed にする。
- report は workflow 本体の戻り値の文字列とする。done に達したときだけ、記録を消す前に同じプロセスで照合の位置を先頭に戻して `workflow` をもう一度呼び、記録をすべて消費して同じ report になることを確かめてから done を出す。2 回目は記録を超える補助関数の呼び出し（`once`、`effect`、`ask`）を実行せず非決定として failed にし、2 回目だけで出た例外も failed にする。そのため GUIDE で、workflow の外（グローバル変数、static）に状態を持つことを禁じる（最後の問いから done までの区間の非決定を実行で見つける。React の StrictMode にあたる）。食い違えば非決定として failed にする。
- 未回答の問いで workflow を抜ける合図は、生成コードの例外処理に捕まらない形にする。Ruby では例外ではなく `throw`（`rescue` では捕まらず、ランタイムの `catch` だけが受ける）、C++ では `std::exception` を継承しない型にする。後始末（Ruby の `ensure`、C++ のデストラクタ）から補助関数を呼ばないことは GUIDE の規則と点検で止め、ランタイムは防衛しない。すり抜けたときは、C++ は異常終了して JSON を出さず、薄い SKILL.md の「JSON でない出力は表示して止まる」で止まる。

検査と点検:

- `check <workflow ファイル>` は構文検査だけを行う。Ruby は `ruby -c`、C++ はランタイムと同じコンパイラとフラグに `-I<langs/cpp>` と `-fsyntax-only` を付ける（workflow が `runtime.hpp` を include するので、ランタイムと合わせて検査される）。
- 点検は、太い SKILL.md の手順で、会話を継承しない新しいサブエージェント（Claude Code は Agent ツール、Codex は `spawn_agent`。調査記録 9）に行わせる。`review.md` のプロンプトの雛形の差し込み口に、ソース、workflow、GUIDE の内容を埋めて渡し（`review-tests.sh` も同じ雛形を機械的に埋める）、渡した内容だけで判断してファイルを読まないようプロンプトで指示する。最初の行に `合格` か `不合格`、続けて指摘を返させる。
- 点検の観点は 2 つ。規則違反は GUIDE の規則（`once` と `effect` の外に不純なもの（時刻、乱数、環境変数、ファイル、コマンド、標準出力への書き込み）がないか、`once` の中で世界を変えていないか、workflow の外に置いた状態、合図を捕まえる例外処理、プロセスの終了、後始末からの補助関数、GUIDE が列挙した標準ライブラリとランタイム以外の `require` や `#include`）に照らす。写しは、ソースの工程の抜けと余計な追加、分岐と繰り返しの条件、問いが LLM にしかできない判断に絞られているか、report の形式を見る。
- 規則違反の相手は不注意な生成コードであって、回避を狙うコードではない。生成コードはチームがレビューして受け入れるので、レビューで一目で分かる回避まで点検の指示で網羅しようとしない。
- 1 回は、workflow を書き、`assemble.sh` を呼び、通れば点検する 1 巡とし、構文検査か点検で落ちたら次の回に進む。回数は `assemble.sh <lang> …` の呼び出しで数え、原因が環境に見えても 3 回試してから報告する。途中の失敗では片付けず、3 回とも通らなければ `assemble.sh --discard <outdir>` で `<outdir>` ごと片付ける。別の手段でコンパイラを呼ぶなどして、検査や点検を回避してはいけない。

言語の前提:

- Ruby は 3.0 以上の標準ライブラリ（json、open3、fileutils など）とバンドル gem の minitest だけを使う。workflow には `set` と `json` をランタイムが読み込んでおき、GUIDE に書く。
- C++ の `command` の一時ファイルは `std::tmpfile` ではなく、run ディレクトリに `mkstemp` で作ってすぐ消す（調査記録 10）。
- C++ は C++17。`<filesystem>` を追加のリンク指定なしで使える環境（GCC 9 以上、Clang 9 以上、macOS 10.15 以上）を前提にし、コンパイラは `${CXX:-c++}` にする。`json.hpp` は `scripts/` にも複製し、workflow も `nlohmann::json` でデータを読み書きしてよい（GUIDE に書く）。
- workflow の入口は Ruby では `workflow` メソッド、C++ では `std::string workflow()` とする。Ruby は `runtime.rb` が `workflow.rb` を読み込み、C++ は `workflow.cpp` が `runtime.hpp` を include して、ランタイムの `main` が `workflow()` を呼ぶ。C++ の単体テストのために、ランタイムの `main` を外してビルドできる形にする。
- C++ の単体テストは doctest v2.5.3 の単一ヘッダ `doctest.h` とライセンス全文（`LICENSE.txt`）を `.coff/test/coff-dullmify/unit/cpp/` に同梱して使う。テスト用なので skill には入れず、開発環境にも追加のインストールを求めない。
- 環境の前提: Claude Code は 2.1.196 以上（`${CLAUDE_SKILL_DIR}` の置換。調査記録 1）、`gh` は 2.95 以上（`gh skill`）、Codex は `multi_agent` が有効な codex-cli（0.153.4 で確認。調査記録 9）。サンドボックス下の挙動は文書で判断し、確認手段はサンドボックスのない環境で行う（調査記録 5）。

薄い SKILL.md:

- 本文は日本語の定型で、HTML コメントを書かない。本文が定型と一致するとは、frontmatter を閉じる `---` の次の空行 1 行を除いた次の行から末尾まで（coff-compile の成果物ではフッタが定型の直後の行に付くので、その最終行を除く）が、定型とバイト単位で一致することを指す。
- 定型のファイル名を `SKILL.md` にしない。`gh skill install` は入れ子の `SKILL.md` を別の skill として列挙し、インストール時に frontmatter を注入する（調査記録 4）。
- frontmatter はソースのものから `allowed-tools` を除いて写し、`allowed-tools: Write Bash(sh ${CLAUDE_SKILL_DIR}/scripts/run *)` を加える。`coff-*` キーの除去は coff-compile が行い、dullmify は coff を知らない。
- 定型が満たす制約: 起動スクリプトは「この SKILL.md と同じディレクトリの `scripts/run`」を絶対パスで、単独のコマンドとして `sh` で呼ばせる（`cd … &&` やパイプを付けると `allowed-tools` の規則に一致しない。`${CLAUDE_SKILL_DIR}` は Codex にないので使わない。調査記録 3、4）。引数と答えはファイルを書くツールで書かせる。stdout の最後の行の JSON で分岐させ（C++ のビルドの失敗のように stderr が混じっても、最後の行が JSON ならそれに従う）、最後の行が JSON でなければ出力を表示して止めさせる。定型の末尾は改行 1 つにする（フッタを付けたときの一致の判定のため）。呼び出しの合間には問いに答える以外の操作をさせず、done では `report` をそのまま表示させ、failed では手順外の対処をさせない。
- 本文に `$ARGUMENTS` を書かない。Codex は展開せず、Claude Code は、プレースホルダがなければ本文の末尾に `ARGUMENTS: <入力>` を付け足す（調査記録 1）。
- 呼び出しが終わらないうちに制御が戻ったときは、終わるまで待って最後の出力を読み、出力がなければ `continue` を呼び直すよう案内する。エージェントを名指ししない書き方にする。

dullmify:

- 引数は `<source> -o <outdir> --lang <lang>` で、どれも必須にし、frontmatter の `description` にこの呼び出し方を書く。`<source>` の frontmatter の値に `---` を含めないことは利用者への前提として太いソースに書き、dullmify は検査しない（調査記録 7）。対応外の言語は、生成の前に `langs/<lang>/GUIDE.md` の有無で確かめ、対応する言語を示してエラーにする。
- 太いソースは言語に依らない規則（問いの書き方、副作用は補助関数で起こすこと、工程ごとのコメント、点検の起動、回数、回避しないこと）だけを持つ。言語ごとの API、規則、入口の名前、workflow のファイル名は GUIDE を、点検の観点と返す形式は `review.md` を読ませ、その中身を太いソースに写さない。
- ソース、GUIDE、`review.md` はファイルを読むツールで読ませる（`cd … && cat …` のような複合コマンドは承認で止まる）。作業ディレクトリの外のソースは Read に承認が要る。失敗したときに原因を別のコマンドで調べさせない（承認で止まり、回数の規則も崩れる）。
- 太いソースの `description` をバッククォートで始めない。YAML の素のスカラーとして読めず、`gh skill install` が frontmatter の注入で失敗する。
- coff-dullmify 自身も Claude Code と Codex の両方で動くよう、本文では同梱ファイルを SKILL.md のディレクトリ基準の相対パスで指す。`allowed-tools` で事前承認するのは `Write` と `sh ${CLAUDE_SKILL_DIR}/assemble.sh *` にし、`assemble.sh` は絶対パスの単独のコマンドとして呼ばせる。
- LLM が書くのは workflow 本体だけで、`<outdir>/scripts/` に GUIDE が定めるファイル名で、`Write` で全体を書く（直すときも `Write` で書き直し、`Edit` は使わない。事前承認が `Write` だけなので。heredoc でも渡さない。調査記録 6）。`<outdir>/SKILL.md` と `<outdir>/scripts/` は `assemble.sh` のもので、`<outdir>` のほかのファイルには触れない。`assemble.sh <lang> <source> <outdir>` は、`<outdir>/scripts/workflow.*` をその場で構文検査し、通らなければ理由（コンパイラの出力を含む）を出して、何も消さずに非 0 で終わる。通れば、`langs/<lang>/` の `GUIDE.md` と `check` 以外（起動スクリプト、ランタイム、C++ では `json.hpp` と `LICENSE.MIT`）を `scripts/` に写し、ソースの frontmatter と定型から薄い SKILL.md を書く。frontmatter の `allowed-tools` は、続くリストの行も含めて置き換える。
- 生成コードには、ソースの工程（番号付きの手順の 1 項目。手順がなければ段落）ごとに、節の見出しと工程の番号をソースの言語でコメントする。
- fixture は `.coff/test/coff-dullmify/fixtures/prefecture.skill.md` とし、複数の問い、問いを含むループ、辞書による分岐、コマンド実行、ファイルの書き込みを通り、中身の決まった report を返すものにする。description は日本語で書く。同じディレクトリに、skill の引数 `prefecture.input` と、期待する report `prefecture.expected`（1 行）を置く。答えの紛れない入力を使い、report の 1 行の形式をソースに文字どおり書く。
- テストと確認の出力は、リポジトリの外（`mktemp -d`）に置く。`gh skill` はリポジトリ内の入れ子の `skills/<name>/SKILL.md` も skill として見つけうる。

coff-compile:

- 「dullmify ビルド」の節に書くのは、起動、`description` の英訳とフッタ、置き換え、lint をかけないこと、`failed` にする条件だけで、薄い SKILL.md の定型や起動スクリプトの規約を写さない。
- `coff-dullmify: <lang>` のソースでは、coff-compile の Lint（§2）を行わない（候補が出ないので §3、§4 も起きない）。「生成物から消しても実行 LLM が手順を完遂できるか」という基準は、実行時にソースを読まない dullmify の成果物には当たらない。
- `coff-dullmify: <lang>` は skill 型の 1 ファイルのソースだけに書け、ほかに付いていれば `failed` にする（同梱ファイルの同期と `scripts/` の置き換えが衝突するため）。coff-compile は `/coff-dullmify <src> -o <一時ディレクトリ> --lang <lang>` を Skill ツールで起動し（SKILL.md を読んで実行する形では coff-dullmify の事前承認が効かない）、一時ディレクトリの SKILL.md の `description` だけを英訳して（`coff-translate: false` なら訳さない）フッタを付け、実体の出力先を一時ディレクトリの内容で置き換える。本文の英訳とコメント除去は行わない。`--ref` や `--agent` の参照 stub は他のソースと同じく正本を指し、`scripts/` は正本の隣にだけ置く。失敗したとき、または coff-dullmify がないときは `failed: <理由>` を報告し、成果物に触れない。
- dullmify のソースでは、skip 判定とフッタの md5 を、ソースと `.claude/skills/coff-dullmify/` のファイル一式（`SKILL.md` を含むパスと内容）をつないだ内容から求める。ランタイムや定型だけが変わっても作り直され、`--force` は要らない。coff-dullmify がなければ `failed` にする。

### 完了条件の確認手段

1. `sh .coff/test/coff-dullmify/run-tests.sh` が終了コード 0 で終わる。駆動スクリプトは、言語ごとに単体テスト（C++ は同梱の doctest、Ruby は minitest）を実行する。単体テストは、記録の書き込みと読み戻し、照合キーの一致と食い違い、`once` の初回と再実行で値の型がそろうこと（Ruby の Symbol が初回から文字列になるなど）、不正な UTF-8 を含む文字列の出力が JSON として読めることを確かめる。続けて LLM 役として `args` と `answer` を書いて `continue` を呼び、各項目を出力の JSON と run ディレクトリの中身で判定する。出力の JSON は `ruby -rjson` で読む。非決定は、テスト用の workflow でわざと `once` の外のサブ秒の時刻を問いの文面に入れて起こす。done の前の確認の再実行は、最後の問いの後でだけ `once` の外のサブ秒の時刻を report に混ぜる workflow が failed になることで確かめる。`effect` の中断は、（C++ は先にビルドを済ませてから）`effect` のブロックの中で `sleep` する workflow を `timeout` で殺してから `continue` を呼び、failed になり run が消えることで確かめる。殺された後の再開は、問いの間に（テスト用なので補助関数の外で）`sleep` を挟む workflow を `timeout` で殺してから、次の `continue` を `timeout` なしで呼び、次の問いに進むことで確かめる。`args` がない run は、書かずに `continue` を呼んで終了コード 2 になり記録ができないことで、未作成の `answer` は、書かずに `continue` を呼んで同じ問いが出て記録が変わらないことで、目印のない run は終了コード 2 で確かめる。副作用の一度性は、`command` が追記するファイルの行数が完走後も 1 であることで（`once` のブロックが初回だけ実行されることは単体テストで数える）、workflow の変更は問いの合間に workflow ファイルに行を足して failed になることで、例外は raise する workflow が failed になり run が消えることで確かめる。構文検査は、`check` が構文の誤りを含む workflow で非 0、正しい workflow で 0 になることを確かめる。
2. `sh .coff/test/coff-dullmify/review-tests.sh` が終了コード 0 で終わる。言語ごとに、fixture を写した workflow のうち、規則違反 5 本（stdout への直接の出力、`once` と `effect` の外のファイルの書き込み、`once` の外の時刻、`once` の中のファイルの書き込み、合図を捕まえる例外処理）、写しの誤り 2 本（工程の抜け、分岐の条件の逆転）、正しいもの 1 本を用意する。欠陥のある 7 本は、正しいものに欠陥を 1 つだけ入れて作る。それぞれについて、`review.md` の雛形に fixture のソース、workflow、GUIDE を埋めたプロンプトを `claude -p` に渡し、最初の行が前の 7 本で `不合格`、最後の 1 本で `合格` になることを確かめる。
3. 確認手段 6 のビルドの後、coff リポジトリのルートを作業ディレクトリにして行う。言語ごとに `mktemp -d` で空の一時ディレクトリを作り、`claude -p --permission-mode default --output-format stream-json --verbose "/coff-dullmify <fixture の絶対パス> -o <一時ディレクトリ> --lang ruby"`（と `cpp`）を実行する。結果の `permission_denials` が空であることと、Agent ツールの呼び出しがあることを確かめる。`<一時ディレクトリ>/SKILL.md` の `allowed-tools` が `Write` と起動スクリプトの規則の 1 行だけであることと、本文が `templates/thin-skill.md` と一致することと、`scripts/` に `run`、`launch`、ランタイム、workflow（C++ では加えて `json.hpp`）があることと、workflow に工程ごとのコメントがあることを確かめる。失敗は、別の空の一時ディレクトリに向けて `CXX=false` を設定した同じコマンドで `--lang cpp` を変換し、`--discard` を除く `assemble.sh` の呼び出しが 3 回あることと、失敗が報告され、そのディレクトリが残らないことで確かめる。Codex では、使い捨ての git リポジトリの `.agents/skills/` を `--dir` で指して `gh skill install --from-local <coff のリポジトリ> coff-dullmify --agent codex` で入れ、そのリポジトリを作業ディレクトリにして（stdin は `/dev/null` にする）`codex exec -s workspace-write "Use the skill coff-dullmify with arguments: <fixture の絶対パス> -o <一時ディレクトリ> --lang ruby"`（と `cpp`）で変換し、出力にサブエージェントの起動（`collab:`）があることと、`allowed-tools` と本文について同じ確認を行う。`CXX=false` での失敗も、Codex で同じく確かめる。あわせて、`<outdir>` にほかのファイルを置いた状態で `assemble.sh --discard <outdir>` を呼び、終了コード 2 で止まって何も消えないことを確かめる。
4. 3 で Claude Code が変換した出力（3 の一時ディレクトリを消さずに残しておく）を、言語ごとに使い捨ての git リポジトリの `.claude/skills/prefecture/` に置き、`claude -p --permission-mode default --output-format json "/prefecture <prefecture.input の内容>"` の結果で、`permission_denials` が空であることと、最後の応答に `prefecture.expected` の 1 行が含まれることを確かめる。同じ出力を `.agents/skills/prefecture/` に置き、`codex exec -s workspace-write "Use the skill prefecture with arguments: <prefecture.input の内容>"` の最後の応答にも同じ 1 行が含まれることを確かめる。暴走の抑止は、fixture の写しに「最初の市の名前を得た後にコマンド `false` を実行し、非 0 なら失敗にする」工程を足したソースを作業ディレクトリの下の一時ディレクトリに置き（作業ディレクトリの外のソースは Read に承認が要る。終わったら消す）、3 と同じコマンドで Ruby に変換し、上と同じ配置で `claude -p --permission-mode default --output-format stream-json --verbose` で動かして、`{"failed":…}` を返した `scripts/run` の呼び出しより後にツール呼び出し（Bash、Write、Edit。拒否されたものも数える）がなく、最後の応答に `failed` の値が逐語で含まれることで確かめる。
5. 確認手段 6 のビルドの後、新しいセッションの対話で行う。fixture の写しに `coff-dullmify: ruby` を足して一時的に `.coff/src/prefecture.skill.md` に置き、`/coff-compile --out <一時ディレクトリ> prefecture` の後に `<一時ディレクトリ>/skills/prefecture/` の `scripts/` と SKILL.md（英訳された description、フッタ、`coff-*` キーがないこと、本文が定型と一致すること）を確かめる。同じコマンドをもう一度実行して何も報告されない（skip）ことを確かめる。続けて `.claude/skills/coff-dullmify/review.md` の末尾に空行を 1 つ足して同じコマンドを実行し、prefecture が作り直される（`compiled`）ことを確かめてから、足した空行と写しを消す。
6. `/compile coff-compile` で coff-compile の新しい成果物を先に作り、新しいセッションで `/compile --force coff-dullmify` を実行し、`diff -r -x SKILL.md .coff/src/coff-dullmify.skill .claude/skills/coff-dullmify` と `diff -r .claude/skills/coff-dullmify skills/coff-dullmify` がどちらも空であることを確かめる。`gh skill install --from-local . coff-dullmify --agent claude-code --dir <一時ディレクトリ>` で導入できることと、`gh skill install --from-local . --agent claude-code --dir <一時ディレクトリ> </dev/null` の一覧に coff-dullmify の下の別 skill が出ないことを確かめる。`grep -n coff-dullmify .coff/src/coff-init.skill.md .claude/skills/coff-init/SKILL.md` で導入対象に入っていることを確かめる。同梱ファイル（`json.hpp` と `LICENSE.MIT` を除く）のコメントとメッセージと本文が日本語であることを読んで確かめ、`langs/cpp/LICENSE.MIT` があることを確かめる。

### 調査記録

1. Claude Code の skill の仕様（https://code.claude.com/docs/en/skills 、2026-09-22 確認）: 「Claude Code substitutes `${CLAUDE_SKILL_DIR}` and `${CLAUDE_PROJECT_DIR}` in two places: the skill's markdown content, and Bash rules in the `allowed-tools` frontmatter」（v2.1.196 以上）。`allowed-tools` は事前承認だけで、他のツールを制限しない。`$ARGUMENTS` は入力した文字列のまま展開され、本文にプレースホルダがなければ末尾に `ARGUMENTS: <入力>` が付け足される。
2. Claude Code のプロセスの扱い（code.claude.com/docs の tools-reference、interactive-mode、sandboxing、settings-reference と、anthropic-experimental/sandbox-runtime @ ddbeb74（v0.0.77）。2026-09-22 確認）:
   - サンドボックスがないとき、呼び出しの後に残ったプロセスの扱いは文書にない。Bash のタイムアウトは既定 2 分、最大 10 分で、タイムアウトした呼び出しはバックグラウンドに移る。`run_in_background` の呼び出しは応答の後も動き続ける。
   - Linux のサンドボックスは bubblewrap を `--unshare-pid`、`--die-with-parent`、`--new-session` で起動する（`linux-sandbox-utils.ts`）。コマンドが終わると PID 名前空間ごと中のプロセスが終了させられ、`test/sandbox/pid-namespace-isolation.test.ts` がこの挙動を確かめている。
   - サンドボックスの中で書けるのは、作業ディレクトリ、`--add-dir` などで足したディレクトリ、`$TMPDIR` が指す利用者ごとの一時ディレクトリだけで、`/tmp` の直下には書けない（読むことはできる）。一時ディレクトリはホストのディレクトリなので呼び出しをまたいで残る。サンドボックスの有無で `$TMPDIR` の解決先が変わる（sandboxing.md の Temporary directories、2026-09-28 に再確認）。
   - macOS（Seatbelt）で残ったプロセスがどうなるかは文書にない。
3. Codex のプロセスと skill の扱い（openai/codex @ fe6455a の codex-rs、2026-09-21 時点）:
   - Linux の `read-only` と `workspace-write` は bubblewrap を `--unshare-pid` 付きで使い（`linux-sandbox/src/bwrap.rs`）、コマンドの終了とともに中のプロセスが終了させられる。サンドボックスがなくても、素の `&` はプロセスグループごと SIGKILL される（`core/src/unified_exec/process.rs` の Drop）。
   - プロセスを生かしてやり取りする正規の手段は unified exec（`exec_command` と `write_stdin`、既定で有効）である。
   - `workspace-write` では `/tmp` と `$TMPDIR` に書き込め、呼び出しをまたいで残る（`protocol/src/protocol.rs`）。
   - skill に `${CLAUDE_SKILL_DIR}` にあたる変数はなく、相対パスは SKILL.md のディレクトリ基準で LLM が解決する（`ext/skills/src/catalog_prompt.rs`）。`allowed-tools` もなく、事前承認は rules ファイル（`.codex/rules/` の `prefix_rule`）で行う。
4. 試作（2026-09-22、scratchpad の使い捨て skill、WSL2）:
   - Claude Code 2.1.278 の `claude -p --permission-mode default` で、`allowed-tools: Bash(sh ${CLAUDE_SKILL_DIR}/scripts/run *)` は `sh <絶対パス>/scripts/run start` を承認なしで通した。`allowed-tools` を外すと承認待ちで止まった。
   - codex-cli 0.155.1 の `codex exec -s workspace-write` は、SKILL.md に書いた `scripts/run` を SKILL.md のディレクトリ基準で解決して実行した。どちらでも `$TMPDIR` は未設定だった（Claude Code はサンドボックスなし）。
   - Codex の `workspace-write` では、`nohup … &` と `setsid nohup … &` のどちらで切り離したプロセスも、次の呼び出しまでに消えていた。Claude Code（サンドボックスなし）では残り、ファイル越しに 2 往復して完走した。
   - gh 2.95.0 の `gh skill install --from-local` は、`scripts/run` の実行権限を落とした。skill の中に入れ子の `templates/SKILL.md` があると、それを別の skill（`t/templates`）として列挙し、インストール時に `metadata.local-path` の frontmatter を注入した。別名の `templates/thin-skill.md` はそのまま残った。
5. 手元の環境（2026-09-28、ruby 3.2.3、g++ 13.3、minitest 5.25.5）には bubblewrap、socat、nlohmann/json、cmake がない。Claude Code のサンドボックスは試せないので、サンドボックス下の動作は調査記録 2 の仕様で判断した。
6. Claude Code 2.1.281 の Bash ツールは、`{`、引用符、`}` をこの順で含むコマンド文字列を「Contains brace with quote character (expansion obfuscation)」として実行前に拒否する（2026-09-25 確認）。引用符付き heredoc の本文も対象で、`dangerouslyDisableSandbox` でも通らない。C++ の関数本体は必ずこれに当たる。`claude -p --permission-mode default` では、skill の `allowed-tools` に `Write` を書くと、作業ディレクトリの外（`/tmp` の下）への Write も承認なしで通る。
7. 薄い SKILL.md の frontmatter の `description` に `` `---` `` を含むと、Claude Code が `allowed-tools` の起動スクリプトの呼び出しを承認しなかった（2026-09-25 確認）。値の中の `---` を閉じ区切りと誤読して後続のキーが落ちるとみられる。
8. 答えを記録してから workflow を再実行する方式では、再実行中のコマンドがエージェントのコマンドタイムアウトを超えて殺されると（調査記録 2、3）、答えは記録済みなのに完走していない run が残る。答えはファイルで渡し、`continue` は取り込んだ後に先頭から再実行するので、同じ `continue` を呼び直せば続きから進む。Ruby で `rescue Exception` は SIGTERM の `SignalException` も捕まえるので、ランタイムが殺されたときに run を消さないよう注意する（2026-09-27 確認）。
9. codex-cli 0.153.4 では `multi_agent` が既定で有効（`codex features list`）で、`codex exec -s read-only` から `spawn_agent` でサブエージェントを起動し、その応答を受け取れた。出力には `collab:` の行が出る（2026-09-28 確認）。同じ版の `codex exec -s workspace-write` は、手元に bubblewrap がなくても同梱のものを使って動き、`spawn_agent` も使えた（廃棄した以前の実装で確かめた。2026-09-28）。
10. glibc の `std::tmpfile` は `$TMPDIR` を無視して `/tmp` に作る（strace で `openat(AT_FDCWD, "/tmp", O_RDWR|O_EXCL|O_TMPFILE, 0600)` を確認。Ubuntu 24.04、2026-09-28）。サンドボックスの中では `/tmp` の直下に書けない（調査記録 2）ので、コマンド実行の一時ファイルは `std::tmpfile` を使わず、run ディレクトリに `mkstemp` で作ってすぐ消す。
11. 6a673ce の実装に対して確認手段 1〜6 を行い、すべて通った（2026-09-29）。差分レビューの指摘を直したあと、確認手段 1 と、bad_branch の点検を両言語で 2 回ずつ行い直した。問い直しのループを抜ける条件を逆にした題材は、Ruby で点検役が 3 回のうち 2 回見落とした。そのため題材は、形式が不正なら失敗する条件を逆にしたものにした（2026-09-29）。起動スクリプトの共通化、`<outdir>` ごとの片付け、UTF-8 の置換の集約の後に、確認手段 1、3、4、6 を行い直して通った。確認手段 5 は `claude -p` では承認が要る操作が拒否されて進めず、行い直していない（2026-09-29）。

### 参考

- `.coff/src/coff-issue-list.skill.md`：埋め込みコマンドと `allowed-tools` でプログラム化した既存例
- issue/2026/09/2222-skill-source-dir.md：ソースのディレクトリ化と同梱（本 issue の前提）
- issue/2026/09/2200-dullmify-lint-mode.md：dullmify の lint モード
- issue/2026/09/2801-polish-reach-implementation-findings.md：dullmify の実装で分かった polish の点検の抜け
