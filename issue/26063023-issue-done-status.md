---
status: done
---
# issue に完了（done）を表す仕組みを追加する

## 背景・目的
issue を作った後、それが完了したことを表す手段が今は無い。
coff の issue は実装の指示書であると同時に、設計判断の長期記憶でもある。
だからこそ、完了したものを単に消すのではなく、完了したと明示したうえで記録として残せる必要がある。
本 issue の目的は、issue の完了状態を表す仕組みを追加することである。

なぜ今これを問題とみなすか（妥当性）。
完了に近い既存要素は「受け入れ条件」のチェックリストだけで、これは個別条件の達成を表すもの。
issue 全体の状態（未完了／完了）を表す欄は存在しない。
よってこれは実在する問題であり、すでに解決済みでもない。

## 現状
- issue は `issue/<yymmddHH>-<slug>.md` の Markdown ファイル（1 issue = 1 ファイル、`coff-detail-issue` 参照）。
- issue 本文は `# <タイトル>` から始まり、YAML frontmatter を持たない。
- 完了・未完了を一覧で見分ける手段も、issue 全体の状態を記録する場所も無い。
- 完了に最も近いのは「受け入れ条件」のチェックリストだが、これは個別条件の達成であって issue 全体の状態ではない。
- issue 同士はファイルパスで相互参照する（「参考・関連 issue」）。現に本 issue とワークフロー再設計 issue は相互にパスで参照している。
- issue を生成・更新するのは `coff-issue-create`（新規作成）と `coff-issue-polish`（解の詰め・上書き）の2スキルで、いずれも frontmatter を書かない・前提しない。

## 変更方針
完了状態を各 issue ファイルの YAML frontmatter に `status` として持たせる。
状態は `open`（未完了）と `done`（完了）の2値とする。
ファイルは元の場所に残し、パスは変えない。
新規 issue は `status: open` で作られ、完了時に専用スキルで `done` へ更新する。

採用理由。
frontmatter に持たせると、ファイルが移動しないので issue 間のパス相互参照が壊れない。
これは「完了しても記録として残す」という長期記憶の目的に整合する。
また `grep 'status: done' issue/*.md` のように機械的に一覧・集計できる。

検討した代替案と却下理由（設計判断の記録）:
- 代替1: 完了 issue を `issue/done/` へ移動する。→ `ls issue/` で進行中だけが見える利点はあるが、「参考・関連 issue」のパス参照が壊れ、完了済みの設計記録が主一覧から隠れる。長期記憶の目的に反するため却下。
- 代替2: 本文先頭に `> 状態: 完了` のような状態マーカー行を置く。→ frontmatter を増やさず最小だが、書式が緩く揺れやすく、機械集計が弱い。却下。
- 代替3: 値域を `todo/doing/done/rejected` まで広げる。→ 進捗や却下設計まで表せるが、現時点の必要は「完了か否か」だけ。YAGNI により2値に絞る。`doing`・`rejected`・完了日フィールドは必要が顕在化したら別 issue で拡張する（リスク・未解決を参照）。
- 代替4: done 化を手編集の運用規約だけで済ませ、専用スキルを作らない。→ 操作は1行の書き換えで済むが、完了マークの操作を手順として明示・再現したいため、専用スキルを新設する（採用）。

## 対象範囲・対象ファイル
- `.coff/src/coff-detail-issue.skill.md`（frontmatter の書式と `status` の意味を共通仕様として定義する）
- `.coff/src/coff-issue-create.skill.md`（新規 issue に `status: open` の frontmatter を付けて生成する）
- 新規 `.coff/src/coff-issue-done.skill.md`（`status` を `done` へ更新する専用スキル）
- `.coff/src/coff-issue-polish.skill.md`（上書き時に既存 frontmatter を保存する旨の一文を足す）
- 上記ソースから `/coff-compile` で再生成される `.claude/skills/<name>/SKILL.md`（成果物は手で編集しない）
- 既存 issue ファイル（`issue/*.md`）への遡及移行は対象外（後述の「absent = open」で扱う）。

## 実装詳細
ソースは日本語で編集し、`/coff-compile coff-detail-issue coff-issue-create coff-issue-done coff-issue-polish` で成果物を再生成する。
成果物は直接編集しない（compile が日本語→英語訳・コメント除去・md5 フッタ付与を行う）。

### frontmatter の書式（coff-detail-issue に定義）
issue ファイルの先頭に次の frontmatter を置く。本文は従来どおり `# <タイトル>` から続ける。

```markdown
---
status: open   # open（未完了）| done（完了）
---
# <タイトル>
```

- `status` の値域は `open` と `done` の2値。
- frontmatter が無い、または `status` が無い issue は `open` とみなす（既存 issue を触らずに済ませるための既定）。
- テンプレートの冒頭にこの frontmatter を追記し、`status` の意味と「absent = open」を明記する。

### coff-issue-create（新規 issue に status を付す）
- issue ファイル生成時に、先頭へ `status: open` の frontmatter を書く。
- 手順のファイル作成ステップに「frontmatter に `status: open` を付ける」を追加する。

### coff-issue-done（新規スキル）
完了マークを付ける専用スキル。`/coff-issue-done <issue ファイル>` で呼ぶ。
1. 対象ファイルを読む。
2. frontmatter があり `status` があれば、その値を `done` に書き換える。
3. frontmatter はあるが `status` が無ければ、`status: done` を frontmatter に追加する。
4. frontmatter が無ければ、ファイル先頭に `---\nstatus: done\n---` を挿入する（本文はそのまま後続させる）。
5. 本文（`#` 以降）は一切変更しない。
6. 更新後のパスと新しい status を報告する。
- 逆方向（`done` → `open` の取り消し）はスキルの対象外とし、手編集で行う（リスク・未解決を参照）。

### coff-issue-polish（frontmatter の保存）
polish は issue を上書き更新するため、既存の frontmatter（`status` を含む）を保存する旨の一文を手順9（上書き）に足す。
polish は `status` の値を変えない（完了判断は done スキルの責務）。

## 受け入れ条件
- [ ] `coff-detail-issue` のテンプレート冒頭に `status: open|done` の frontmatter が定義され、`status` の意味と「frontmatter/`status` が無ければ open とみなす」が明記されている
- [ ] `coff-issue-create` が新規 issue に `status: open` の frontmatter を付けて生成する手順になっている
- [ ] 新規スキル `coff-issue-done` のソースが `.coff/src/coff-issue-done.skill.md` にあり、`/coff-compile` で `.claude/skills/coff-issue-done/SKILL.md` が生成される
- [ ] `coff-issue-done` が、frontmatter 有無の両方で `status` を `done` にでき（無ければ挿入）、本文を変更しない
- [ ] `coff-issue-polish` の上書き手順に「既存 frontmatter を保存し、`status` を変えない」旨がある
- [ ] 対象ソースを編集し `/coff-compile` で成果物が再生成されている（成果物を手で編集していない）

## テスト方針
ドッグフードで検証する。
- `coff-issue-create` を1回かけ、生成された issue が `status: open` の frontmatter を持ち、本文が `# タイトル` から始まることを確認する。
- その issue に `/coff-issue-done` をかけ、`status: done` に変わり、本文が無変更であることを確認する。
- frontmatter を持たない既存 issue（例: `issue/26062803-import-tech-write-ja.md`）に `/coff-issue-done` をかけ、先頭に `status: done` の frontmatter が挿入され、本文が無変更であることを確認する（確認後は変更を破棄する）。
- 同 issue を `coff-issue-polish` にかけ、上書き後も `status` の frontmatter が保存されることを確認する。
- `grep -l 'status: done' issue/*.md` で完了 issue を機械的に一覧できることを確認する。
- `/coff-compile coff-detail-issue coff-issue-create coff-issue-done coff-issue-polish` を実行し、4件が `compiled` になることを確認する。

## 人間が決めた判断
- [x] 完了状態は frontmatter の `status` に持たせる（本文マーカー・ディレクトリ移動は却下）。理由: ファイルが動かず相互参照が壊れない、長期記憶に整合、grep で集計できる。
- [x] `status` の値域は `open`／`done` の2値にする。理由: 現時点の必要は完了か否かだけ。`doing`・`rejected`・完了日は必要が顕在化したら別 issue で拡張。
- [x] done 化は専用スキル `coff-issue-done` を新設して行う（手編集の運用規約のみで済ませる案は却下）。理由: 完了マークの操作を手順として明示・再現したい。
- [x] 既存 issue へ frontmatter を遡及付与しない。理由: 遡及は既存記録に触るリスクがあり、「frontmatter/`status` が無ければ open」という既定で不足なく扱える。次に create/done/polish が触れた時点で自然に付く。

## リスク・未解決
- 値域の拡張余地。`doing`（進行中）・`rejected`（却下した設計を記録として残す終端状態）・完了日フィールドは、必要が顕在化した時点で別 issue として拡張する。今回は2値に絞った。
- 取り消し操作。`done` → `open` の差し戻しはスキルの対象外とし手編集で行う。頻度が低い想定だが、必要なら done スキルに引数で状態を渡す拡張を検討する。
- frontmatter を壊さない担保。create は新規に付与、done は付与・更新、polish は保存する。3スキルが frontmatter を破壊しないことを受け入れ条件とテストで担保する。特に polish の上書きは本文再生成なので、frontmatter の取りこぼしに注意する。
- 既存 issue の非移行。`issue/26062803` など frontmatter の無い issue は当面 open 扱いのまま残る。一覧の網羅性を厳密にしたくなったら、一括付与を別途検討する。

## 参考・関連 issue
- 関連: `issue/26062822-improve-issue-workflow.md`（issue ワークフローの役割分担と品質の見直し。本 issue はそこから切り出した）
- issue 運用の共通仕様: `.coff/src/coff-detail-issue.skill.md`
- 生成・更新スキル: `.coff/src/coff-issue-create.skill.md` / `.coff/src/coff-issue-polish.skill.md`
- compile パイプライン: `.coff/src/coff-compile.skill.md`
- 経緯: 本 issue は当初一度 create したが、解を含みすぎたため破棄し、問題空間だけで立て直した。その後 polish で解決空間を詰めた。
