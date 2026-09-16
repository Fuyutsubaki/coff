---
name: coff-compile
description: coff のソース (`.coff/src/`) を実行中 agent の配置先を既定として実行用成果物にビルドする。`.skill.md` → skills、`.outputstyle.md` → output-styles、`.agent.md` → agents。引数なしで全件、`<name>` 指定で個別ビルド、`--lint-only` で事前チェックのみ、`--force` で未変更ソースも再ビルド。`--out` / `--ref` / `--agent` で出力先・参照 stub・agent 別の出力に対応。
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

ソース種別ごとに出力先が決まる。`<name>` はファイル名から `.<type>.md` を取り除いたもの、`<root>` は後述の規則で導出した出力ルート。

| ソース glob | 出力パス |
|---|---|
| `.coff/src/*.skill.md` | `<root>/skills/<name>/SKILL.md` |
| `.coff/src/*.outputstyle.md` | `<root>/output-styles/<name>.md` |
| `.coff/src/*.agent.md` | `<root>/agents/<name>.md` |

## オプション

引数で以下を受け付ける:

- `--lint-only`: lint だけ実行してそこで止める。コンパイル前の確認も行わない。
- `--force`: md5 一致によるスキップを無視して、対象すべてを処理する。
- `--out <root>`: 実行中 agent から導出する既定の出力ルートを置き換える。種別ごとのサブレイアウト（`skills/<name>/SKILL.md` など）はルート配下でそのまま使う。
- `--ref`: `--out` と併用して、skill はコンパイル済み本文の複製ではなく正本への参照 stub を出力する。`--out` なしで指定されたらエラーとして中断する。
- `--agent <name>`: agent 名から出力ルートを決めるプリセット（後述の表）。複数指定は各プリセットの出力を合算する。明示の `--out` / `--ref` と同時に指定されたらエラーとして中断する。
- `<path|name> [<path|name> ...]`: 指定したソースだけを処理する。フルパス `.coff/src/foo.skill.md` や `.coff/src/foo.outputstyle.md`、ベース名 `foo`、ファイル名 `foo.skill.md` のいずれでも受け付ける。指定がなければ全 glob を対象にする。ベース名 `foo` が複数の種別に一致する場合（`foo.skill.md` と `foo.outputstyle.md` が両方ある等）は曖昧として報告し、フルパスかファイル名での指定を求める。

例:
- `--lint-only` — 全件 lint のみ（md5 一致のものはスキップ）。
- `--force` — md5 を無視して全件再ビルド。
- `foo` — foo だけ lint+compile。
- `my-style` — my-style の output style だけビルド。
- `--agent codex` — codex 向けの出力を `.agents/skills/` に出す（実行中 agent が codex でなければ参照 stub）。

## agent プリセットと参照出力

この SKILL.md の配置パスが `.claude/skills/` 配下なら実行中 agent は claude-code、`.agents/skills/` 配下なら codex と判別する。 <!-- 環境変数で判別しないのは、codex にセッションを識別する安定した変数が無いため -->

判別できなければユーザーに聞き、対話できなければ推測せずエラーとして中断する。
以降、`<current-agent>` は判別した agent、`<current-root>` はその agent に対応する次の出力ルートを指す。
user scope に配置されていても、出力ルートはカレントリポジトリ直下とする。

| agent | 出力ルート |
|---|---|
| `claude-code` | `.claude/` |
| `codex` | `.agents/` |

<!-- codex は project scope で `.agents/skills/*/SKILL.md` を発見する（`gh skill install --agent codex` の配置先と同じ）。`.agents/` は agent 横断の標準ディレクトリなので、対応 agent を増やすときはこの表に行を足す -->

- オプションで出力先を明示しなければ `<current-root>` を出力ルートとし、skill の実体を置く。
- `--agent` で指定した agent が `<current-agent>` ならそのルートに skill の実体を置き、他の agent ならそのルートに `<current-root>` の正本を指す参照 stub を置く。 <!-- 実体を複数箇所に置くと更新漏れで drift するため -->
- skill の正本は常に `<current-root>/skills/<name>/SKILL.md` とし、`--out` で出力ルートを置き換えても正本の位置は変えない。
- `--out` 単独なら指定先に skill の実体を置き、`--ref` もあれば指定先に正本への参照 stub を置く。
- 参照 stub の相対パスは、stub を置くディレクトリから正本までを計算して求める。`../` の数を固定しない。 <!-- 出力ルートの深さを変えても参照を解決できるようにするため -->
- claude-code 固有の種別（outputstyle / agent 型）は正本／参照を区別せず、`.claude/` に置く 1 つを常に実体とする。
  agent から導出した出力ルートに `.claude/` が含まれるときだけ対象にし、含まれなければレポートにも出さない。
  `--out` で出力ルートを明示した場合は、指定先に全種別の実体を出す。
- 参照 stub は正本と同じ frontmatter（`coff-*` キー除去後）を持ち、本文を正本への相対パス 1 行として、同じ規則でフッタを付ける。

  ```markdown
  ---
  name: <name>
  description: <正本と同一>
  ---

  This file is a reference. Read and follow `<relative-path-to-canonical>`.
  <!--{"src":".coff/src/<name>.skill.md","md5":"<src md5>"} -->
  ```

- ビルド順は実体 → 参照とする。
- 参照を書くとき `<current-root>` の正本が存在しないか、それ自体が参照 stub ならエラーとして報告する。 <!-- 参照だけを書いて、どこにも実体のない相互参照を作らないため -->

## 1. 対象ファイルの選定

ソースの拡張子から種別を判定し、出力先をキー、期待する配置モード（実体または参照）を値とする連想配列 `dsts` を導出する。

出力ルートと配置モードは前節の規則で決める。

```bash
declare -A dsts   # 出力先 -> 期待する配置モード（body=実体 / ref=参照）
case "$src" in
  *.skill.md)       name=$(basename "$src" .skill.md);       rel="skills/$name/SKILL.md" ;;
  *.outputstyle.md) name=$(basename "$src" .outputstyle.md); rel="output-styles/$name.md" ;;
  *.agent.md)       name=$(basename "$src" .agent.md);       rel="agents/$name.md" ;;
  *) echo "unknown source type: $src"; continue ;;
esac
src_md5=$(md5sum "$src" | cut -d' ' -f1)
ref_prefix='This file is a reference. Read and follow `'
verdict=skip
for dst in "${!dsts[@]}"; do
  dst_md5=$(tail -n 1 "$dst" 2>/dev/null | grep -oP '"md5":"\K[a-f0-9]{32}')
  [ "$src_md5" = "$dst_md5" ] || verdict=build
  if [ "${dsts[$dst]}" = ref ]; then
    canonical=$(realpath -m --relative-to="$(dirname "$dst")" "$current_root/skills/$name/SKILL.md")
    grep -qxF "${ref_prefix}${canonical}\`." "$dst" 2>/dev/null || verdict=build
  else
    grep -qF "$ref_prefix" "$dst" 2>/dev/null && verdict=build
  fi
done
echo $verdict
```

スキップは全出力先の md5 が一致し、参照先では期待する参照行が文字列一致し、実体の出力先では参照行の形がないときに限る。 <!-- 実体と参照、または参照先だけが違う stub はソースが同じなら md5 も同じになるため -->

`--out` / `--agent` があるときも、参照出力を含む全出力先を `dsts` に加え、同じフッタ規則と配置モードの規則で skip を判定する。

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

候補があれば、複数選択できる問い合わせで一度に提示する（選択式の質問ツールがあればそれを使い、なければ番号付き一覧で聞く）。

- 候補はファイル単位でまとめ、各ラベルに「該当行、引用、適用方法、推奨、適用後のプレビュー」を含める。
- 推奨はラベルの先頭タグで示す。推奨される候補は `[推奨]`、ユーザー判断が必要な候補は `[要判断]`。 <!-- 質問ツールに事前選択がないため -->
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

c. **フロントマターの構造を保つ。** 先頭の `---` … `---` ブロックは出力でも有効な YAML フロントマターであり続けること。ソースにフロントマターがなければエラーで中断する。`coff-` で始まるキーは出力の frontmatter からすべて取り除く。 <!-- ビルド指示（ラッパー skill が拡張するものを含む）の名前空間であって、実行時情報ではないため -->

d. **出力を書き、フッタを付ける。** フッタは最終行に置き、本文の後、コードブロックの外に書く。output-style ファイルにもフッタを付ける。プレーンな markdown なので末尾の HTML コメントは無害で、スキップ判定にも使う。参照モードの出力先には、本文の代わりに「agent プリセットと参照出力」の stub を書く。`$content` は、その出力先の配置モードが実体なら本文、参照なら stub の本文（いずれもフッタ手前まで）。

   ```bash
   for dst in "${!dsts[@]}"; do
     mkdir -p "$(dirname "$dst")"
     content=$(build_content "${dsts[$dst]}" "$dst")   # body なら本文、ref なら stub の本文
     printf '%s\n<!--{"src":"%s","md5":"%s"} -->\n' "$content" "$src" "$src_md5" > "$dst"
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
