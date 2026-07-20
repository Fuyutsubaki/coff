---
name: coff-compile
description: coff のソース (`.coff/src/`) を `.claude/` の実行用成果物にビルドする。`.skill.md` → skills、`.outputstyle.md` → output-styles、`.agent.md` → agents。frontmatter で `coff-dist` を宣言した skill は配布用 `skills/` にも二重出力する。引数なしで全件、`<name>` 指定で個別ビルド、`--lint-only` で事前チェックのみ、`--force` で未変更ソースも再ビルド。`--out` で出力先の置換、`--ref` で参照 stub の出力、`--agent` で codex など agent ごとの既定に従った出力ができる。
license: MIT
coff-dist: true
---

<!--
コンパイル:
- ソースを英語にするなどして、実行時のトークンを節約する
- skill をソースと成果物に分けることで、管理のしやすさと実行コストを両立させる

lint:
- 控えめな最適化である
- コンパイルで機械的に処理するとまずそうな最適化を、「ユーザーに許可を取りながらソースを都合の良い形式に変える」という方向で実現する
-->

## 入出力

ソース種別ごとに出力先が決まる。`<name>` はファイル名から `.<type>.md` を取り除いたもの。

| ソース glob | 出力パス |
|---|---|
| `.coff/src/*.skill.md` | `.claude/skills/<name>/SKILL.md` |
| `.coff/src/*.outputstyle.md` | `.claude/output-styles/<name>.md` |
| `.coff/src/*.agent.md` | `.claude/agents/<name>.md` |

skill 型のうち frontmatter に `coff-dist: true` を持つものは、`skills/<name>/SKILL.md` にも同一内容（フッタ含む）を出力する。 <!-- gh skill の発見規約（skills/*/SKILL.md）に合わせた配布用の二重出力。何を配布するかは repo 固有の判断なので、compile 本体でなくソース側の宣言に持たせる。issue/2026/07/1921-gh-skill-installable.md の判断 -->

入力 glob の集合は上表の全 glob。引数がなければこれら全 glob を対象にする。

## オプション

引数で以下を受け付ける:

- `--lint-only`: lint だけ実行してそこで止める。コンパイル前の確認も行わない。
- `--force`: md5 一致によるスキップを無視して、対象すべてを処理する。
- `--out <root>`: 出力ルート（既定 `.claude`）を置き換える。種別ごとのサブレイアウト（`skills/<name>/SKILL.md` など）はルート配下でそのまま使う。
- `--ref`: `--out` と併用して、コンパイル済み本文の複製ではなく正本への参照 stub を出力する。`--out` なしで指定されたらエラーとして中断する。
- `--agent <name>`: agent 名から `--out` と `--ref` を決めるプリセット（後述の表）。複数指定できる。指定がなければ `claude-code` 相当。明示の `--out` / `--ref` はプリセットより優先する。
- `<path|name> [<path|name> ...]`: 指定したソースだけを処理する。フルパス `.coff/src/foo.skill.md` や `.coff/src/foo.outputstyle.md`、ベース名 `foo`、ファイル名 `foo.skill.md` のいずれでも受け付ける。指定がなければ全 glob を対象にする。ベース名 `foo` が複数の種別に一致する場合（`foo.skill.md` と `foo.outputstyle.md` が両方ある等）は曖昧として報告し、フルパスかファイル名での指定を求める。

例:
- `/coff-compile --lint-only` — 全件 lint のみ（md5 一致のものはスキップ）。
- `/coff-compile --force` — md5 を無視して全件再ビルド。
- `/coff-compile foo` — foo だけ lint+compile。
- `/coff-compile my-style` — my-style の output style だけビルド。
- `/coff-compile --agent codex` — codex 向けの参照 stub を `.agents/skills/` に出力。

## agent プリセットと参照出力

実体（正本）はリポジトリにちょうど 1 箇所とし、他の agent 向けには参照 stub を置く。 <!-- 実体を複数箇所に置くと更新漏れで drift するため -->

| agent | 出力ルート | 配置モード | 対象種別 |
|---|---|---|---|
| `claude-code`（既定） | `.claude/` | 実体 | skill / outputstyle / agent |
| `codex` | `.agents/` | 参照 | skill のみ |

<!-- codex は project scope で `.agents/skills/*/SKILL.md` を発見する（`gh skill install --agent codex` の配置先と同じ）。`.agents/` は agent 横断の標準ディレクトリなので、対応 agent を増やすときはこの表に行を足す -->

- claude-code 固有の種別（outputstyle / agent 型）は、他 agent のビルドでは対象外として扱い、レポートにも出さない。
- 参照 stub は正本と同じ frontmatter（`coff-*` キー除去後）を持ち、本文は正本への相対パス 1 行とする。フッタも同じ規則で付け、skip 判定に使う。

  ```markdown
  ---
  name: <name>
  description: <正本と同一>
  ---

  This file is a reference. Read and follow `../../../.claude/skills/<name>/SKILL.md`.
  <!--{"src":".coff/src/<name>.skill.md","md5":"<src md5>"} -->
  ```

- ビルド順は正本 → 参照。参照を書くとき正本が存在しなければエラーとして報告する。

## 1. 対象ファイルの選定

ソースの拡張子から種別を判定し、出力先の集合 `dsts` を導出する。

```bash
case "$src" in
  *.skill.md)       name=$(basename "$src" .skill.md);       dsts=".claude/skills/$name/SKILL.md"
                    sed -n '2,/^---$/p' "$src" | grep -q '^coff-dist:[[:space:]]*true' && dsts="$dsts skills/$name/SKILL.md" ;;
  *.outputstyle.md) name=$(basename "$src" .outputstyle.md); dsts=".claude/output-styles/$name.md" ;;
  *.agent.md)       name=$(basename "$src" .agent.md);       dsts=".claude/agents/$name.md" ;;
  *) echo "unknown source type: $src"; continue ;;
esac
src_md5=$(md5sum "$src" | cut -d' ' -f1)
verdict=skip
for dst in $dsts; do
  dst_md5=$(tail -n 1 "$dst" 2>/dev/null | grep -oP '"md5":"\K[a-f0-9]{32}')
  [ "$src_md5" = "$dst_md5" ] || verdict=build
done
echo $verdict
```

スキップは全出力先の md5 が一致するときに限る。

`--out` / `--agent` があるときは、この導出に出力ルートの置換と参照出力の追加を適用する。参照出力も `dsts` に加え、skip 判定は全出力先に同じフッタ規則で行う。

空のソースはエラーとして報告し、次のファイルへ進む。

## 2. Lint

選定した各ソースについて、以下のパターンを検出する。

| 候補 | 適用方法 | 推奨 |
|---|---|---|
| 設計の動機や全体像の説明（WHY） | `<!-- -->` で囲う | ON |
| 読者向けの注意書き（「手で編集するな」など） | `<!-- -->` で囲う | ON |
| 同じことを言い回しを変えて繰り返す文（特に「肯定形 X。否定形 X。」のような対句） | 後続文を削除 | ON |
| 条件文に対する対偶や Yes/No の重複説明（「Yes→A / No→B」の箇条書き、または「X なら Y。X でなければ Y しない」型） | 重複側を削除 | ON |
| 同じ内容の重複（frontmatter `description` と冒頭段落など） | 削除または統合 | OFF |
| H1 見出しと frontmatter `name` の重複 | 削除 | OFF |
| frontmatter `description` が冗長 | 短縮 | OFF |
| 構造の重複（高レベルな要約セクションと詳細セクション群が同じ手順を二度説明している） | 要約側を削除 | OFF |
| 冗長な例示（汎用ルールの直後に網羅的な組み合わせ例。`combinable` などと書いてあるのに全組み合わせを並べる） | 代表例 2-3 件まで絞る | OFF |

判定基準: その文を**生成物から消した**ときに、実行 LLM が手順を完遂できるか？完遂できるなら候補に挙げる。

検出対象から除外するもの:
- すでに `<!-- -->` の内側にあるもの。
- フロントマター内、コードブロック内、インラインコード内。

ただし frontmatter `description` だけは別にチェックする。skill ソースでは「何をするか」と「ユーザーがどう呼ぶか（引数や呼び出し方）」以外のもの（内部手順、実装詳細、WHY）が含まれていたら短縮候補（推奨 OFF）として、削るべき箇所を引用しつつ短縮案を提示する。agent ソースの `description` はモデルがサブエージェント起動を判断する材料なので skill と同じ扱い（WHAT＋いつ起動するか以外、つまり内部手順、実装詳細、WHY を短縮候補とし、推奨 OFF）。output style ソースには引数や呼び出し方の概念がないため、WHAT（何のためのスタイルか）以外を短縮候補（推奨 OFF）として扱う。

## 3. 対話による承認

候補があれば、`AskUserQuestion` の `multiSelect=true` で一度に提示する。

- 候補はファイル単位でまとめ、各ラベルに「該当行、引用、適用方法、推奨、適用後のプレビュー」を含める。
- 推奨はラベルの先頭タグで示す。推奨される候補は `[推奨]`、ユーザー判断が必要な候補は `[要判断]`。 <!-- AskUserQuestion に事前選択がないため -->
- ユーザーが選んだものだけソースに反映する。

反映の仕方:
- コメント化候補: 該当範囲を `<!-- ... -->` で囲う。文言そのものは変えない。
- 削除・書き換え候補: 提示した書き換え案で置き換えるか、該当行を削除する。

候補が多くて一度に提示しきれない場合は、ファイル単位 → セクション単位の順で分けて順番に提示する。

## 4. コンパイル前の確認

lint で候補が 1 件でも提示されていれば（実際に適用したかどうかは問わない）、コンパイルに進む前に改めて確認する。

> "Lint 完了。N 件適用、M 件却下。コンパイルしますか？"

却下されたら中止する。承認されたら 5 へ進む。

## 5. コンパイル

lint がソースを書き換えた場合は、フッタを書く前に md5 を取り直す。 <!-- §1 で取った md5 は lint で書き換えると古くなる --> 各対象ファイルについて:

a. **日本語を英語に訳す。** 散文・見出し・箇条書き、および frontmatter の `description` 値を簡潔な英語に書き直す。 <!-- 出力のトークン削減のため --> ソースの frontmatter に `coff-translate: false` があれば、この工程は丸ごと行わない（本文も `description` も原文のまま出力する）。 <!-- 日本語の書き方そのものが内容のスキルは、英訳すると価値が壊れるため -->

   ただし以下は訳さない（バイト単位でそのまま残す）:
   - モデルが照合や逐語出力に使う引用符付きリテラル。例: `ファイル名が "注文" から始まるファイル` の `"注文"` は日本語のまま。周囲の文だけを訳す → `files whose name starts with "注文"`。
   - コード識別子、関数名、ファイルパス、CLI フラグ、正規表現、コマンド引数。
   - フェンスコードブロック（` ``` … ``` `）とインラインコードの中身。
   - フロントマターのキー、`name` の値、識別子として機能するその他のフロントマター値。
   - 固有名詞（製品名・プロジェクト名・人名）。
   - UI 文字列、エラーメッセージ、その他ユーザーやモデルが逐語的に再現すべき文字列。

   迷ったら原文のまま残す。

b. **本文中の HTML/markdown コメントを取り除く。** 本文の `<!-- ... -->` をすべて除去する。フェンスコードブロックやインラインコードの中にあるコメントは触らない。フロントマターも触らない。

c. **フロントマターの構造を保つ。** 先頭の `---` … `---` ブロックは出力でも有効な YAML フロントマターであり続けること。ソースにフロントマターがなければエラーで中断する。`coff-translate` と `coff-dist` のキーは出力の frontmatter から取り除く。 <!-- ビルド指示であって実行時情報ではないため -->

d. **出力を書き、フッタを付ける。** フッタは最終行に置き、本文の後、コードブロックの外に書く。output-style ファイルにもフッタを付ける。プレーンな markdown なので末尾の HTML コメントは無害で、スキップ判定にも使う。参照モードの出力先には、本文の代わりに「agent プリセットと参照出力」の stub を書く。

   ```bash
   for dst in $dsts; do
     mkdir -p "$(dirname "$dst")"
     printf '%s\n<!--{"src":"%s","md5":"%s"} -->\n' "$body" "$src" "$src_md5" > "$dst"
   done
   ```

## 6. レポート

各ソースについて以下のいずれかを報告する:
- `compiled`（lint で適用した件数があれば併記）
- `linted (N applied, M rejected)` — `--lint-only` のとき、またはコンパイル前の確認で却下されたとき
- `failed: <reason>`

スキップしたファイルは出さない。`--lint-only` で lint 候補が 0 件のときも何も出さない。

## ルール

- ソースを書き換えるのは lint で承認されたものだけ。
- frontmatter の `name` 値、出力パスを構成する識別子は lint でも触らない。
- lint も compile も、途中で失敗したら中途半端な書き込みを残さない。

<!--
実装メモ:
- 推奨 ON / OFF の境目は「ソースの意味が失われるか」。コメント化は意味を残すので推奨 ON。
- lint で何も承認されなくても、ユーザーが「コンパイルする」と答えれば既存の md5 のまま compile に進む（その場合は md5 差分スキップで結局スキップされる可能性あり）。
-->
