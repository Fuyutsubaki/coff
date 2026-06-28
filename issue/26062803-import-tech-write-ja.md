# tech-write-ja を coff に取り込み、日本語ライティング規範を使えるようにする

## 背景・目的
日本語テクニカルライティングの規範 tech-write-ja を coff に取り込む。
coff で日本語を書くとき（issue 本文、ドキュメント、必要なら skill ソース）に、この規範を参照・適用できる状態にするのが目的。
原典は k16shikano の gist であり、それを f4ah6o が SKILL 形式で公開している。

## 現状
- [f4ah6o/tech-write-ja](https://github.com/f4ah6o/tech-write-ja)（default branch: `main`）は2つの skill を持つ。`skills/japanese-tech-writing/SKILL.md`（文章規範、約147行）と `skills/argument-gap-edit/SKILL.md`（論証の点検と編集、約45行）。
- 各ファイルは Claude Code 形式の SKILL.md である。frontmatter に `name` と `description` を持ち、本文は日本語。coff の成果物 `.claude/skills/<name>/SKILL.md` と同じ形式。
- `argument-gap-edit` は冒頭で `../japanese-tech-writing/SKILL.md` を読むことを前提にする。両者は兄弟ディレクトリに置く必要がある。
- ライセンスは Unlicense（パブリックドメイン相当）。作者 k16shikano が原典 gist のコメントで明言し、参照 gist（https://gist.github.com/k16shikano/67625f2a7d96e3bbdfae8d571a936063）に LICENSE 全文がある。取り込み・改変・再配布は自由。リポジトリ直下の GitHub API `license` が `null` なのは LICENSE ファイルを置いていないためで、ライセンス自体は確定している。README と各 SKILL.md に k16shikano の gist への出典表記がある。
- coff 側に日本語ライティング規範の仕組みはまだない。
- coff の skill は `.coff/src/*.skill.md`（日本語ソース）を `/coff-compile` で `.claude/skills/<name>/SKILL.md`（英訳済み）に変換するパイプラインで管理する。入力 glob は `.coff/src/*` のみ。
- 取り込みは GitHub CLI 公式の `gh skill` を使う。`gh skill` は v2.90.0（2026-04-16, public preview）で追加された公式コマンドで、tech-write-ja の README の `gh skill install` はこの構文。既定は project スコープで、リポジトリの `.claude/skills/` に通常ファイル（コピー、symlink ではない）として入る。日本語のまま入り、翻訳は起きない。frontmatter に `metadata.github-repo` などの由来情報が付く。要 gh ≥ v2.90.0。

## 変更方針
方針の要は「これらは日本語の文章規範なので、英訳してはならない」点にある。
coff-compile は日本語ソースを英語に訳す。tech-write-ja を通常の `.coff/src/` に置いて compile すると、規範本文が英訳され、さらに「中黒」「ダッシュ」「鉤括弧」など日本語固有の照合用リテラルや例が壊れる。これは目的に反する。
したがって、英訳を通さずそのまま取り込む（vendoring）。取り込みは公式 `gh skill` でコピーし、git にコミットする。

手順:
1. `gh skill install` で2つの skill を `.claude/skills/` に原文コピーし、git にコミットする。出典表記はコピー元に含まれるのでそのまま残る。
2. これらは vendored（coff-compile の対象外）として扱う。`.coff/src/` に対応ソースを置かないので、`/coff-compile` の入力 glob に掛からず touch されない。既存挙動のままで安全。
3. care-giver 方針（`.claude/` を手で編集しない）に vendored 例外を明記する。`.coff/src/care-giver.outputstyle.md` を編集し、(a) vendored skill の存在と再取得コマンド（`gh skill update`）、(b) 日本語を書くときは japanese-tech-writing に従う、の2点を薄く追記して再 compile する。これにより「再生成レシピ」が `/coff-compile` ではなく `gh skill` 側にあることを記録し、孤児化を防ぐ。
4. coff-detail-issue に、issue 本文（日本語）は japanese-tech-writing の規範に従う旨を一文追加する（ソース編集と再 compile）。

## 対象範囲・対象ファイル
- 新規（vendored、原文ママ）: `.claude/skills/japanese-tech-writing/SKILL.md`、`.claude/skills/argument-gap-edit/SKILL.md`
- 編集（ソース編集して compile）: `.coff/src/care-giver.outputstyle.md`、`.coff/src/coff-detail-issue.skill.md`
- 取得元: `f4ah6o/tech-write-ja` の `skills/` 配下（`main` ブランチ）

## 実装詳細
前提: gh ≥ v2.90.0（`gh skill` 対応）。公式 apt リポジトリ（`cli.github.com/packages`）から入れている場合は `sudo apt-get update && sudo apt-get install --only-upgrade gh` で更新する。

取り込み（公式 `gh skill`）:

```bash
gh skill preview f4ah6o/tech-write-ja japanese-tech-writing   # 中身を確認（未検証skillのため）
gh skill preview f4ah6o/tech-write-ja argument-gap-edit
gh skill install f4ah6o/tech-write-ja japanese-tech-writing --agent claude-code
gh skill install f4ah6o/tech-write-ja argument-gap-edit    --agent claude-code
# -> .claude/skills/japanese-tech-writing/ と .claude/skills/argument-gap-edit/ に原文コピー
```

更新は `gh skill update`、確認は `gh skill list`。

ゼロ依存の fallback（gh を上げられない場合は `gh api` で直接コピー）:

```bash
for n in japanese-tech-writing argument-gap-edit; do
  mkdir -p ".claude/skills/$n"
  gh api "repos/f4ah6o/tech-write-ja/contents/skills/$n/SKILL.md" --jq '.content' | base64 -d > ".claude/skills/$n/SKILL.md"
done
```

- vendored ファイルには coff の md5 footer（`<!--{"src":...,"md5":...} -->`）を付けない。由来は `gh skill` が付ける frontmatter の `metadata.github-repo` と、本文先頭の k16shikano gist 出典表記で残る。
- `.coff/src/care-giver.outputstyle.md` と `.coff/src/coff-detail-issue.skill.md` はソースを編集し、`/coff-compile care-giver coff-detail-issue` で再生成する。
- `argument-gap-edit` の相対参照 `../japanese-tech-writing/SKILL.md` は、両者が `.claude/skills/` 直下の兄弟になるので解決する。

## 受け入れ条件
- [ ] `.claude/skills/japanese-tech-writing/` と `.claude/skills/argument-gap-edit/` が原文のまま存在し、英訳されていない
- [ ] 両 skill が Skill 一覧にロードされる
- [ ] `argument-gap-edit` から `../japanese-tech-writing/SKILL.md` を辿れる
- [ ] care-giver に vendored 例外と「日本語は japanese-tech-writing に従う」が追記され、compile 済み
- [ ] coff-detail-issue に issue 本文の規範参照が追記され、compile 済み
- [ ] `/coff-compile` 実行時に vendored skill が処理対象に出ない
- [ ] vendored の2ディレクトリが git にコミットされ、`gh skill update` で更新できる
- [ ] 出典（k16shikano、f4ah6o）と Unlicense である旨が取り込み箇所に残る

## テスト方針
- 取り込み後、skill 再読込で2 skill が一覧に出ることを確認する。
- `/coff-compile` を引数なしで実行し、vendored 2件が処理対象に出ないこと、care-giver と coff-detail-issue が `compiled` になることを確認する。
- 日本語の文章（例として既存 issue 本文）に japanese-tech-writing を適用し、規範どおりに推敲できることを試す。
- `argument-gap-edit` を起動し、併用規範の読み込み（相対パス）が成功することを確認する。

## リスク・未解決
- ライセンスは解決済み（Unlicense）。取り込み・改変・再配布は自由で、マージのブロッカーではない。Unlicense は表示義務を課さないが、礼儀として出典（k16shikano、f4ah6o）を残す。
- 取り込み方式の代替案。vendoring の代わりに、coff-compile に「英訳しない passthrough」モード（frontmatter フラグや `.raw.skill.md` 拡張子など）を追加し、`.coff/src/` で管理する案もある。今回は変更が大きいので vendoring を推奨する。将来 vendored が増えるなら再検討する。
- 適用範囲の判断。「日本語を使えるようにする」の対象を issue 本文だけにするか、coff の日本語出力全体（ドキュメント、PR 説明など）に広げるか。推奨は care-giver で全体に薄く促し、coff-detail-issue で issue を明示する形。広げ方はユーザー判断。
- vendored の更新運用。上流が更新されたときは `gh skill update` で取り込み直す。自動化（定期実行など）は当面しない。
- gh のバージョン依存。`gh skill` は v2.90.0+ が必要。取り込み・更新の時だけ要るランタイム依存で、コピー後の利用時には不要。古い環境では `gh api` fallback を使う。

## 参考・関連 issue
- https://github.com/f4ah6o/tech-write-ja
- 原典: https://gist.github.com/k16shikano/fd287c3133457c4fd8f5601d34aa817d
- coff の compile パイプライン: `.coff/src/coff-compile.skill.md`
