---
status: open
---
# skill のソースをディレクトリで書けるようにし、中のファイルを同梱して配る

`.coff/src/<name>.skill/SKILL.md` のようにソースをディレクトリで書いた skill を coff-compile でビルドし、同じディレクトリのファイルを成果物に同梱して、配布ミラーまで届ける。
coff-dullmify のランタイムのように、SKILL.md 以外のファイルがないと動かない skill を coff のソースから作るためである。

## 目的

coff の skill はソース 1 ファイルから SKILL.md を 1 つ作るだけで、スクリプトなどのファイルを同梱できない。
coff-dullmify（issue/2026/09/2200-add-dullmify.md）は、言語ごとのランタイムや起動スクリプトを同梱して配る必要がある。
本 issue の目的は、ファイルを同梱する skill を `.coff/src/` のソースから作り、`.claude/skills/` と配布ミラー `skills/` まで届けられるようにすることである。

## 現状

- coff-compile（`.coff/src/coff-compile.skill.md`）はソース `.coff/src/*.skill.md` を `.claude/skills/<name>/SKILL.md` の 1 ファイルに出力し、skip 判定はそのフッタの md5 とソースの md5 の比較で行う。出力パスの導出（§1）と引数でのソースの指定は、`.skill.md` の 1 ファイルを前提にしている。
- ラッパー compile（`.coff/src/compile.skill.md`）は `.coff/src/*.skill.md` の frontmatter から `coff-dist` を読み、配布ミラーへは `SKILL.md` 1 ファイルを `cmp` と `cp` で複製する。
- `gh skill install` は skill ディレクトリをサブディレクトリごとコピーし、`--from-local` ではコミットしていないファイルも読む。`.coff/src/` の下の `SKILL.md` は skill として見つけない（調査記録 1）。
- 今の `.claude/skills/` と `skills/` の coff skill には、`SKILL.md` 以外のファイルがない（vendored の grilling の `LICENSE` を除く）。

## 設計方針

1. ソースの形を 2 つにする。これまでの 1 ファイルの `.coff/src/<name>.skill.md` と、ディレクトリの `.coff/src/<name>.skill/`（`SKILL.md` と同梱ファイル）である。同梱ファイルのない skill は 1 ファイルのままでよく、既存のソースは移さない。同じ名前が両方の形にあればエラーにする。
2. ディレクトリのソースの `SKILL.md` は、1 ファイルのソースと同じ経路でコンパイルし、skip もフッタの md5 で判定する。
3. 同梱ファイルは別の段で同期する。成果物の `SKILL.md` 以外のファイルがソースと違えば、消してから写し直す。`SKILL.md` と同梱ファイルを別々に判定するので、同梱ファイルだけを変えても `SKILL.md` は訳し直されない。英訳は実行ごとに揺れるので、訳し直すと `SKILL.md` に無用な差分が出る。
4. ミラー同期は、`coff-dist` を宣言した skill の `.claude/skills/<name>/` と `skills/<name>/` をディレクトリごと一致させる（追加、更新、削除）。`coff-dist` は両方の形のソースから読む。

- ソースと同名のディレクトリ（`.coff/src/<name>.skill.md` と `.coff/src/<name>/`）に同梱ファイルを置く案は採らない：一つの skill のソースがファイルとディレクトリに分かれる。
- issue/2026/08/0501-coff-include-directive.md の `coff-include` で同梱する案は採らない：あれは別の skill を `references/` に写す仕組みで、skill 自身の手書きのファイルを置く場所にならない。
- 対象外：既存のソースのディレクトリ化、参照 stub（`--ref`、`--agent codex`）への同梱（stub は正本を指し、同梱ファイルは正本の隣にある）、同梱ファイルの英訳、シンボリックリンク。

## 決めたこと

- skill のソースを `.coff/src/<name>.skill/SKILL.md` のディレクトリで書けるようにし、同じディレクトリのファイルを同梱する（ファイルとディレクトリが分かれているのはかえって不自然）

## 完了条件

- [ ] ディレクトリのソースをビルドすると、成果物の SKILL.md はこれまでと同じ規則でコンパイルされ、ほかのファイルはソースとバイト単位で一致し、それ以外のファイルがない。`--out` を付けたときも、置き換えた出力ルートの下に同じ形で入る
- [ ] 同梱ファイルを変えたとき、足したとき、消したときに成果物の同梱ファイルが更新され、消したファイルは成果物からも消える。そのとき SKILL.md は訳し直されない。どれも変えなければ skip される
- [ ] 既存の 1 ファイルのソースは、実装の後の `/compile` で成果物もミラーも変わらない（この issue で直したソースの分を除く）
- [ ] 同じ名前のソースが両方の形にあると、エラーになる
- [ ] `coff-dist` を宣言したディレクトリのソースは、`/compile` で配布ミラー `skills/<name>/` にディレクトリごと同期され、`gh skill install` で同梱ファイルごと導入できる

## 実装メモ

### 実装詳細

- `.coff/src/coff-compile.skill.md`：ディレクトリのソースを、選定、引数、入出力の表、同梱ファイルの同期の対象に加える
- `.coff/src/compile.skill.md`：`coff-dist` を両方の形から読み、ミラーをディレクトリごと同期する

後で効く制約:

- ディレクトリのソースは `.coff/src/*.skill/SKILL.md` で見つけ、名前はディレクトリ名から `.skill` を除いたものとする。`SKILL.md` のないディレクトリはソースとして扱わない。
- 引数では、1 ファイルのソースの 3 つの形（フルパス、ファイル名、ベース名）に合わせて、`.coff/src/foo.skill`（末尾の `/` も可）、`foo.skill`、`foo` だけを受け付ける。同じ名前が両方の形にあるときは、その名前が処理の対象に入っていれば（引数なしなら常に）エラーとして報告して次へ進む。この判定は、種別をまたぐ既存の曖昧さの規則より先に行う。
- フッタは 1 ファイルのソースと同じ形で、`src` は `.coff/src/<name>.skill/SKILL.md`、`md5` はその md5 とする。lint、英訳、コメント除去、frontmatter の処理（§2 と §5 の a〜c）は `SKILL.md` だけに行う。
- 同梱ファイルの差は `diff -r -x SKILL.md <ソースのディレクトリ> <成果物のディレクトリ>` で見て、同期の後にこの差がなくなっていることを保つ。同期は実体の出力先にだけ行い、参照 stub はこれまでどおり SKILL.md だけを書く。`--force` のときは、SKILL.md をコンパイルし直し、同梱ファイルも写し直す。同期が途中で止まっても、次の実行で差として見つかって直る（受容）。
- 同期は、SKILL.md が skip か compiled で終わったときだけ行う。SKILL.md が failed のとき、コンパイル前の確認で却下されたとき、`--lint-only` のときは行わないので、`SKILL.md` のない成果物ディレクトリはできない。SKILL.md の md5 がフッタと一致し、同梱ファイルだけが違うときは、lint をかけずに同期だけを行い、`compiled` と報告する。
- 入れ子の `SKILL.md` は書き方の規則で禁じるだけで、検査はしない（`diff -r -x SKILL.md` はどの深さの `SKILL.md` も比べない）。
- 同梱ファイル（`.md` を含む）は英訳もコメント除去もせずに、そのまま写す。issue/2026/09/2200-add-dullmify.md の定型やガイドは、この前提で書かれる。
- coff-compile の入出力の節に、ディレクトリのソースの書き方として、同梱ファイルはそのまま写されること、同梱ファイルに `SKILL.md` という名前を使わないこと（`gh skill` が別の skill として見つける。調査記録 1）を書く。`--out` の説明の「`skills/<name>/SKILL.md` など」は `skills/<name>/` にする。
- coff-compile の `description` では、種別の説明を「`.skill.md` / `.skill/` → skills」の形にするだけにとどめ、同梱の詳細は本文に書く。この issue の理由の説明を skill の本文に入れるときは、`<!-- -->` の中に書く。
- coff-compile のルールに、ディレクトリのソースを 1 ファイルに戻したとき成果物に残る同梱ファイルは手で消す、と書く（compile の「宣言を外したソースのミラー削除は手動で行う」と同じ扱い）。
- ミラーは、差があったときだけ `mirrored: <name>` と報告する。`.claude/skills/<name>/` がなければ、ミラーを消さない。
- `.coff/src/` の外のソースは扱わない（これまでどおり）。

### 完了条件の確認手段

確認には、使い捨てのディレクトリのソース `.coff/src/zz-bundle-sample.skill/` を使う。中身は、日本語の description、`coff-dist: true`、HTML コメントを持ち、lint の候補が出ない本文の `SKILL.md`、`a.txt`、HTML コメントを含む `sub/b.md` とする。確認が終わったら、そのソースと `.claude/skills/zz-bundle-sample/`、`skills/zz-bundle-sample/` を消す。3 の後半から先は新しい成果物で動かす必要があり、lint の問いに答えることもあるので、新しいセッションで人が行う。一時ディレクトリは、リポジトリの外に `mktemp -d` で作る。実行する順は 3、1、2 と 5、4 とする（3 はサンプルを置く前にしか行えない）。

1. `/coff-compile --out <一時ディレクトリ> zz-bundle-sample` の後に、`diff -r -x SKILL.md .coff/src/zz-bundle-sample.skill <一時ディレクトリ>/skills/zz-bundle-sample` が空で、`SKILL.md` が英訳され、HTML コメントと frontmatter の `coff-dist` がなく、フッタが `{"src":".coff/src/zz-bundle-sample.skill/SKILL.md","md5":"<その md5>"}` であることを確かめる。`/compile zz-bundle-sample` でも `.claude/skills/zz-bundle-sample/` について同じことを確かめる。
2. 1 の `/compile` の直後に、`.claude/skills/zz-bundle-sample/SKILL.md` の本文の末尾（フッタの前）に目印の行を手で足しておく。`sub/b.md` を変える、`c.txt` を足す、`a.txt` を消す、をそれぞれ行って `/compile zz-bundle-sample` を実行し、毎回 `compiled` が報告され、1 の `.claude/skills/zz-bundle-sample/` についての `diff -r` が空になり、目印の行が残っている（訳し直されていない）ことを確かめる。何も変えずにもう一度実行し、何も報告されないことを確かめる。
3. `zz-bundle-sample` を置く前に `/compile` を実行し、`git status --short .claude skills` に出るのが coff-compile と compile の成果物とミラーだけであることを確かめる。この 1 回目は古い成果物が新しいソースをビルドするので、続けて新しいセッションで、新しい成果物を使ってもう一度 `/compile` を実行し、何も報告されず `git status --short .claude skills` が 1 回目の後から変わらないことを確かめる。
4. `.claude/skills/zz-bundle-sample/` の各ファイルの md5 を控え、`.coff/src/zz-bundle-sample.skill/SKILL.md` の写しを `.coff/src/zz-bundle-sample.skill.md` に一時的に置く。引数なしの `/coff-compile` と `/coff-compile zz-bundle-sample` のそれぞれで、両方の形にあることを理由とするエラーが報告され、控えた md5 が変わらないことを確かめてから、写しを消す。
5. 2 の各回の後に `diff -r .claude/skills/zz-bundle-sample skills/zz-bundle-sample` が空であることを確かめる。最後に `gh skill install --from-local . zz-bundle-sample --agent claude-code --dir <一時ディレクトリ>` を実行し、`diff -r -x SKILL.md .coff/src/zz-bundle-sample.skill <一時ディレクトリ>/zz-bundle-sample` が空であることを確かめる（`SKILL.md` には gh がメタデータを注入するので比べない）。

### 調査記録

1. gh 2.95.0 での試作（2026-09-22、scratchpad の使い捨てリポジトリ）: `gh skill install --from-local . --agent claude-code --dir <dir> </dev/null` の一覧に、`.coff/src/x.skill/SKILL.md` は出なかった。コミットしていない `skills/u/SKILL.md` と `skills/u/sub/b.txt` は、`gh skill install --from-local . u` でサブディレクトリごと導入された。skill の中の入れ子の `SKILL.md` は別の skill として列挙される（issue/2026/09/2200-add-dullmify.md の調査記録 4）。

### 参考

- issue/2026/09/2200-add-dullmify.md：この仕組みを使う最初の skill（coff-dullmify）
- issue/2026/08/0501-coff-include-directive.md：別の skill を `references/` に同梱する計画。ミラーのディレクトリ単位の同期は、本 issue（2222）が入れたものを使える
- issue/2026/07/1921-gh-skill-installable.md：配布ミラーと `coff-dist` の由来
