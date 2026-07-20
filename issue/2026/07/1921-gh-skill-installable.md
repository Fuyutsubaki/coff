---
status: done
---
# coff のスキルを gh skill でインストール可能にする

## 要約

`/coff-compile` に二重出力の規則を足し、frontmatter で `coff-dist` を宣言したスキルを `gh skill` の発見規約に合う `skills/<name>/SKILL.md` にも書き出す。
vendored 依存は grilling の規律を本文に吸収し、日本語系 2 つを `coff-` prefix で第一級ソースに取り込んで解消する。
新スキル coff-init と MIT の LICENSE を加え、`gh skill install Fuyutsubaki/coff coff-init` → `/coff-init` の 2 手で他環境に導入できる状態にする。

## 背景・目的

coff は「skill as a code」を掲げ、スキルをソース（`.coff/src/`）からビルドして管理する repo である。
しかし現状の配置ではスキルを他環境に配る手段がなく、使うには repo を clone して手で配置するしかない。
`gh skill install` は Claude Code を含む多数のエージェントに対応した配布経路であり、これに乗せればワンコマンドでインストールできるようになる。
さらに coff のスキルは vendored スキル（japanese-tech-writing など）を参照しており、スキル単体を配っても導入先で参照が空振りする。
本 issue の目的は、配布レイアウトと依存の両方を解決し、coff のスキル群を最短の手数で他環境に導入できる状態にすることである。

## 現状

- coff のスキル成果物は `.claude/skills/<name>/SKILL.md` に置かれ、ソースは `.coff/src/<name>.skill.md` にある。成果物は `/coff-compile` でビルドされ、手編集は禁止されている。コンパイルは本文の日本語を英訳する。
- `gh skill` のスキル発見規約は `skills/*/SKILL.md` / `skills/{scope}/*/SKILL.md` / ルート直下の `*/SKILL.md` / `plugins/{scope}/skills/*/SKILL.md` の 4 パターンであり、`.claude/skills/` はどれにも合致しない。実際に `gh skill publish --dry-run` を repo で実行すると「no skills found」になる。
- 試行として `skills/coff-detail-issue/SKILL.md` に成果物を仮置きしたところ、`gh skill publish --dry-run` は発見・検証に成功し、`gh skill install --from-local . coff-detail-issue --agent claude-code --dir <一時dir>` でのインストールも成功した。コンパイル footer（末尾の HTML コメント）が付いたままでも検証は通る。
- `gh skill install` の書式は `gh skill install <repository> [<skill[@version]>]` で、一度に指定できるスキルは 1 つである。スキル名を省略すると一覧の対話選択になり、非対話環境では何も導入されない。
- dry-run では 2 件の警告が出た。frontmatter に推奨フィールド `license` がないこと、`.claude/skills/` に他作者のスキルがあるので `.gitignore` に入れるべきとの指摘である。
- repo は public だが LICENSE ファイルがなく、法的には閲覧できても再利用できない状態である。
- 配布対象の coff スキルは vendored に依存している。
  - japanese-tech-writing（f4ah6o/tech-write-ja、Unlicense。本文冒頭に k16shikano 氏の gist への出典表記あり）: detail・create・polish・care-giver が本文の文章規範として常時参照する。強い依存。
  - argument-gap-edit（f4ah6o/tech-write-ja、Unlicense）: polish の手順 9 と care-giver が論証点検で参照する。弱い依存。
  - grilling（mattpocock/skills、MIT）: create・polish が「一問ずつ聞く」規律を条件付きで借用する。弱い依存。借用箇所は `.claude/skills/grilling/SKILL.md` をパスで読む指示になっている。
  - codex-delegate（自作・配布対象外）: polish の試験実装が「別プロセスで実行する場合」に限り参照する。条件付きで、なくても手順は成立する。

## 変更方針

変更は 3 本柱で構成する。

**1. 配布レイアウト: `/coff-compile` の二重出力。**
skill 型のソースのうち配布を宣言したものは、`.claude/skills/<name>/SKILL.md` に加えて同一内容を `skills/<name>/SKILL.md` にも書き出し、両方を repo にコミットする。
`skills/` は gh skill の発見規約に合致するので、これだけで `gh skill install Fuyutsubaki/coff <skill>` が成立する見込みである。
配布対象の判定は、ソース frontmatter のビルド指示 `coff-dist: true` で行う（`coff-translate` と同系で、キーは出力の frontmatter から除去する）。
coff-compile は他 repo にも配布する汎用ツールなので、「`coff-` 名なら配布」という coff 固有のポリシーを compile 本体に埋め込まない（人間の決定）。
当初は変更が compile 内で完結する名前規則を採ったが、この汎用性の理由で frontmatter 宣言に置き換えた。
導入先のユーザーが自作スキルを配布する用途にも、同じ宣言がそのまま使える。
配置の代替案は次の理由で却下した。

- `skills` と `.claude/skills` を symlink で繋ぐ案: GitHub 上の symlink の扱いと他 OS での checkout に不確実性がある。
- ルート直下に `<name>/SKILL.md` を置く案: 発見規約には合うが、repo ルートにスキルディレクトリが並んで散らかる。
- 正本を `skills/` に移し `.claude/skills` 側をリンクにする案: Claude Code がリンク先を解決するか未確認でリスクがある。

**2. 依存解消: grilling は吸収、日本語系は第一級ソース化。**
vendored 依存を性質で使い分けて解消し、vendored への依存をゼロにする（人間の決定）。

- grilling: 借用している規律（一問ずつ聞く・各問に推奨案を添える・コードで分かることは聞かずに自分で調べる）を create / polish の本文に自分の言葉で書き込み、`.claude/skills/grilling/SKILL.md` を読む指示を削除する。言い換えによる吸収なので MIT の表示義務は生じない。vendored の grilling 本体は配布物でも依存でもなくなるが、単体利用のため手元には残す。
- japanese-tech-writing / argument-gap-edit: `coff-japanese-tech-writing` / `coff-argument-gap-edit` に改名して `.coff/src/` のソースに取り込み、第一級の coff スキルにする。Unlicense（パブリックドメイン相当）なので改名・改変・MIT での再頒布まで法的に自由である。本文冒頭の出典表記は残す。`coff-dist: true` を付けて配布対象にする。取り込み後は上流の更新に追従しない（人間の決定。以後は coff が正本）。
- 取り込みに伴い、コンパイルの英訳規則と衝突する問題を解く。日本語系 2 つは「日本語の書き方そのもの」が内容であり英訳すると価値が壊れるため、ソース frontmatter に翻訳スキップ指示 `coff-translate: false` を新設し、compile はこの指示があるとき英訳を行わない（指示キー自体は成果物から除去する。AI の判断）。

依存解消の代替案は次の理由で却下した。

- vendored を `skills/` に同梱して再配布する案: 上流との乖離と二重管理が生じ、他作者のスキルを coff 名義の配布物に混ぜることになる。
- coff-init で上流から導入を自動化する案（本 issue の旧方針）: 導入は自動化できるが、上流の移転・消滅・版ずれのリスクが残り続ける。取り込みならスキルの完全性を coff 自身が保証できる。
- README で別途インストールを案内する案: 手作業が残り、本 issue の動機を解消しない。

codex-delegate は配布しない決定を維持する。polish の参照は条件付きで、なくても手順が成立するためそのままにする。

**3. 導入の入口と体裁: coff-init・ライセンス・README。**
導入先で実行する入口スキル coff-init を新設する（ソース `.coff/src/coff-init.skill.md`。`coff-dist: true` で配布対象にする）。
`gh skill install` は 1 コマンド 1 スキルしか受けないため、coff-init が兄弟スキルの一括導入と導入先の初期化（`issue/` 作成、CLAUDE.md への規約追記、運用フローの案内）を担う（守備範囲は人間の決定）。
CLAUDE.md への追記を含めるのは、「成果物を手編集せずソースからビルドする」という coff の根幹規約が output style と利用者の memory に住んでいて、gh skill の配布経路では運ばれないためである。
init の追加候補のうち、報告への更新・コミット運用の案内と導入後の自己検証は見送った（人間の決定）。
repo ルートに MIT の LICENSE ファイルを追加する（人間の決定）。
dry-run の推奨警告に応え、配布対象スキルのソース frontmatter に `license: MIT` を追加する。
README.md に導入手順（coff-init 起点の 2 手）を追記する。

`gh skill publish`（release 作成と `agent-skills` topic 付与）は人間の決定によりスコープ外とする。必要になったら別 issue を立てる。

## 実装詳細

触る範囲は次のとおり。ビルド規則とスキルの変更はソース（`.coff/src/`）のみを編集し、成果物の再生成は人間が `/coff-compile` を実行する（成果物の手編集は禁止）。

- `.coff/src/coff-compile.skill.md`:
  - 出力規則に「frontmatter に `coff-dist: true` を持つ skill 型は `skills/<name>/SKILL.md` にも同一内容（footer 含む）を書く」を追記する。スキップ判定は全出力先の footer md5 が一致するときだけ skip とする（`skills/` 側が欠けていれば再ビルド）。`coff-dist` キーは `coff-translate` と同様に出力の frontmatter から除去する。
  - 翻訳スキップを追加する。ソース frontmatter に `coff-translate: false` があるとき手順 5a の英訳を行わず、このキーは成果物の frontmatter から除去する。
- `.coff/src/coff-japanese-tech-writing.skill.md` / `.coff/src/coff-argument-gap-edit.skill.md`（新規）: 現在の vendored の SKILL.md 本文を移す。frontmatter は `name` を新名称に変え、上流の install メタデータ（`metadata.github-*`）を落とし、`license: MIT` と `coff-translate: false` を付ける。冒頭の出典表記は保持する。argument-gap-edit の本文にある相互参照 `../japanese-tech-writing/SKILL.md` は `../coff-japanese-tech-writing/SKILL.md` に書き換える。旧 vendored ディレクトリ `.claude/skills/japanese-tech-writing/` / `.claude/skills/argument-gap-edit/` はコンパイル後に削除する（同内容のスキルが新名で並ぶのを防ぐ）。
- `.coff/src/coff-issue-create.skill.md` / `coff-issue-polish.skill.md`: grilling をパスで読む指示を削り、規律（一問ずつ・推奨案を添える・コードで分かることは調べる）を本文に書き込む。japanese-tech-writing への言及を新名称に置換する。polish は argument-gap-edit への言及も新名称に置換する。
- `.coff/src/coff-detail-issue.skill.md` / `care-giver.outputstyle.md`: japanese-tech-writing / argument-gap-edit への言及を新名称に置換する。care-giver の vendored 例外の記述を「grilling のみ」に更新する。
- `.coff/src/coff-init.skill.md`（新規）: 手順は次の骨子とする。
  1. 前提確認: 導入先が git repo であること、`gh` CLI と `gh skill` サブコマンドが使えること。欠けていれば報告して中断する。
  2. 兄弟スキルの導入: `.claude/skills/` を見て不足している coff スキル（coff-detail-issue / coff-issue-create / coff-issue-polish / coff-issue-done / coff-compile / coff-japanese-tech-writing / coff-argument-gap-edit）を `gh skill install Fuyutsubaki/coff <name> --agent claude-code` で 1 つずつ導入する。`--agent` を省くと非対話時の既定が github-copilot になり `.claude/skills/` に入らないため、明示は必須である。不足判定はスキルディレクトリの有無だけで行い、版の新旧は見ない。
  3. 初期化: `issue/` ディレクトリがなければ作成する。導入先の CLAUDE.md に coff の規約節を追記する。内容は「`.claude/` 配下の coff 成果物は手編集しない。変更は `.coff/src/` を編集して `/coff-compile` でビルドする。issue 運用の入口は coff-issue-create」の要点を数行で。CLAUDE.md がなければ作成し、既に coff の節があれば何もしない（再実行しても重複しない）。既存の記述には触れず末尾に節を足すだけとする。
  4. 報告: 導入結果と issue 運用フロー（create → polish → 実装 → done）、coff-compile を使う場合は `.coff/src/` 規約が必要になることを短く案内する。
- 配布対象 8 ソース（coff-compile / coff-detail-issue / coff-issue-create / coff-issue-polish / coff-issue-done / coff-init / coff-japanese-tech-writing / coff-argument-gap-edit）: frontmatter に `license: MIT` と `coff-dist: true` を追加する。
- `LICENSE`: MIT 全文。copyright は `2026 Fuyutsubaki`。
- `README.md`: 導入手順として「`gh skill install Fuyutsubaki/coff coff-init --agent claude-code` → 導入先 repo で `/coff-init`」を追記する。個別導入（対話選択の `gh skill install Fuyutsubaki/coff`）も可能である旨を添える。

## 検証

- [x] `gh skill publish --dry-run` が `coff-` の 8 スキルちょうどを発見し、license の警告が出ない — 確認: repo ルートでコマンドを実行し出力を読む
- [x] `gh skill install --from-local . coff-init --agent claude-code --dir <一時dir>` が成功し、SKILL.md が配置される — 確認: コマンド実行後に一時 dir を確認
- [x] 配布 8 スキルについて `skills/<name>/SKILL.md` と `.claude/skills/<name>/SKILL.md` の内容が一致する — 確認: `diff` で比較
- [x] coff-japanese-tech-writing / coff-argument-gap-edit の成果物本文が日本語のまま（英訳されていない）で、`coff-translate` キーが frontmatter に残っていない — 確認: 成果物を目視
- [x] 配布 8 スキルの本文に vendored への参照（`grilling` / 旧名 `japanese-tech-writing` / 旧名 `argument-gap-edit` のスキル参照やパス）が残っていない — 確認: `grep` で走査
- [x] coff-init の手順 2〜3 のコマンド列が一時 git repo で成立する（マージ前はリモートに `skills/` がないため `--from-local` で代替確認する） — 確認: 一時 repo でコマンドを実行し `.claude/skills/` / `issue/` / CLAUDE.md の追記を確認（CLAUDE.md は再実行で重複しないことも見る）
- [x] LICENSE がルートにあり MIT 全文である — 確認: 目視
- [x] README に coff-init 起点の導入手順が載っている — 確認: 目視

## 人間が決めた判断

- 配布対象は名前が `coff-` で始まるスキルとする。codex-delegate は配布しない。（2026-07-19）
- 今回は発見規約に合うレイアウトまでとし、`gh skill publish` は踏まない。（2026-07-19）
- ライセンスは MIT を付与する。（2026-07-20）
- coff-init を導入の入口とし、守備範囲は兄弟スキル導入に加え導入先の環境セットアップも含める。（2026-07-20）
- coff-init は導入先 CLAUDE.md への規約追記まで行う。更新・コミット運用の案内と導入後の自己検証は見送る。（2026-07-20）
- coff-compile は汎用スキルとして保ち、coff 固有の配布ポリシー（`coff-` 名での判定）を埋め込まない。配布対象はソース側の `coff-dist: true` 宣言で指定する。（2026-07-20）
- vendored 依存の解消は、当初の coff-init による上流からの導入自動化を改め、grilling は規律の本文吸収、日本語系 2 つは `coff-` prefix での第一級ソース化（fork。以後上流に追従しない）とする。（2026-07-20）

決定の実体は変更方針に記載。

## リスク・未解決

- リモートからの install はデフォルトブランチへのマージ後にしか確認できない。from-local での成功を代替確認とし、マージ後に `gh skill install Fuyutsubaki/coff coff-init` と `/coff-init` の通し実行で追認する。
- 日本語系 2 つは fork なので上流（f4ah6o/tech-write-ja）の改善が自動では入らない。取り込み時点の内容を正本として coff が保守する。
- 翻訳スキップ `coff-translate: false` は compile の新機構であり、キー除去を含めて実装の実挙動で確認が要る。
- coff-init は兄弟スキル名と repo 名（Fuyutsubaki/coff）をハードコードする。スキル追加で古くなるが、検出機構は持たない（init 実行時の install 失敗として顕在化する）。
- dry-run の警告「`.claude/skills/` を `.gitignore` に入れるべき」は、成果物と vendored をコミットする coff の設計と衝突するため受容する。発見対象は `skills/` のみで、残る vendored（grilling）が配布物に混ざることはない。
- スキル本文の相互参照は `.claude/skills/<name>/SKILL.md` のパス表記のままにする。claude-code エージェントとしてインストールすれば同じパスに入るが、`.agents/skills` を共有する他エージェントでは参照が切れる。今回は Claude Code 利用者を対象とし、他エージェント対応はしない。
- `gh skill` は preview 機能であり、発見規約や検証仕様は予告なく変わりうる。

## 参考・関連 issue

- `.coff/src/coff-compile.skill.md` — 出力規則・翻訳スキップを追記する対象（ビルドの正本）
- `.claude/skills/japanese-tech-writing/SKILL.md` / `.claude/skills/argument-gap-edit/SKILL.md` — 取り込み元の vendored 本文
- `gh skill publish --help` / `gh skill install --help` — 発見規約・検証仕様・install 書式の出典
