---
status: done
---
# coff スキルの claude 前提を外し、claude と codex の両方で動くことを検証するテストを加える

配布対象の skill 本文が claude 固有の配置・記法・ツール名を前提にしており、`gh skill install --agent codex` で導入すると相互参照と初期化が成立しない。
参照を相対パスに統一し、記法とツール名を機能で書き、coff-init に agent 判別を持たせる。
検証は、両 agent の配置に導入して参照解決と禁止パターンを見る静的検査と、両 CLI で skill を実行する E2E の 2 本で行う。

## 目的

coff は agent 横断で使う汎用ツールだが、配布対象の skill 本文が claude の配置（`.claude/skills/`）、記法（`/name`）、ツール名（`AskUserQuestion`）を前提にしている。
解けた状態は、同じ配布物が claude-code と codex のどちらの配置に導入されても動作し、相互参照の解決と coff-issue-done の完走を静的検査と E2E で確かめられることである。
claude 固有の種別（output style / agent 型）、coff repo 内でしか使わない非配布 skill（compile / care-giver / codex-delegate）、codex 以外の agent は扱わない。

## 現状

- coff-issue-create / polish / done と coff-detail-issue は、共通仕様を `.claude/skills/coff-detail-issue/SKILL.md` の配置で参照している。
  `gh skill install --agent codex` は `.agents/skills/<name>/SKILL.md` に入れるので参照が切れる。issue/2026/07/1921-gh-skill-installable.md はこれを承知で先送りした。
  coff-argument-gap-edit だけは `../coff-japanese-tech-writing/SKILL.md` の相対参照で、両配置で解決する。
- coff-init は `--agent claude-code` と CLAUDE.md への追記を固定し、規約文も `.claude/` を指す。README の導入コマンドも同じ。
- 呼び出しと例示を `/coff-compile` のスラッシュ記法で書いている。codex の明示呼び出しは `$name`。
- coff-compile の lint 承認は claude のツール名 `AskUserQuestion` を名指ししている。
- coff-issue-list は claude の埋め込み実行（`!` フェンスと `$ARGUMENTS`）に依存する。codex では LLM がブロックを読んで自分で実行し引数も通るが（試行で確認）、本文にその指示はない。
- サブエージェントは codex にもある（multi_agent は stable）。claude 前提なのは polish の「fork ではない」の但し書きと、codex-delegate への無条件の参照だけ。
- テストと CI は無い。

## 設計方針

- 相互参照は「その SKILL.md があるディレクトリ」基準の `../<name>/SKILL.md` に統一する。両 agent の配置で同じ形で解決し、repo 内の `--agent codex` stub 経由でも正本側で解決する（両 CLI で試行済み）。
- 呼び出しは記法を書かず「<name> skill を実行する」と書く。ユーザー向けの例示は引数だけを示し、接頭辞が agent 依存であることを一言添える。
- agent 固有のツール名は書かず、機能で書く。
- coff-init は実行中の agent を自身の配置場所で判別する（`.claude/skills/coff-init` なら claude-code、`.agents/skills/coff-init` なら codex）。導入の `--agent`、規約ファイル（CLAUDE.md / AGENTS.md）、規約文中の skill ディレクトリをそれに合わせる。規約文のビルド指示は codex なら `--out .agents` にする（coff-compile の codex プリセットは `.claude/` の正本への参照 stub で、codex 単独では成立しない）。
- coff-issue-list は claude 固有の `!` フェンスをやめ、普通の bash ブロックと「実行して出力を提示する」の一文にする。どの agent でも同じ手順で動き、claude では Bash 呼び出しが 1 回増える。
- サブエージェントの語は残す。「fork ではない」は「会話を継承しない」に言い換え、codex-delegate 参照は「導入されている場合のみ」に統一する。
- テストは `test/static.sh` と `test/e2e.sh` の 2 本。static は配布物を両 agent の配置に `--from-local` で導入し、参照解決と禁止パターンを検査する。e2e は両 CLI を非対話で起動し、相対参照を辿る coff-issue-done が完走することを見る。

却下した案: 全 skill を `.agents/skills/` に一本化する（Claude Code 2.1.272 は `.agents/` を発見しない）。環境変数で agent を判別する（codex にセッションを識別する安定した変数が無い）。coff-issue-list の `!` フェンスを残して未展開時の注記で分岐させる（agent ごとに動き方が変わる）。
CI への組み込みと coff repo 自身の `.agents/` ビルドは対象外とし、必要なら別 issue にする。

## 決めたこと

- テストは静的検査スクリプトと両 CLI の E2E の両方を作る
- coff-issue-list は注記で分岐させず、どちらの agent でも同じ形式で動く bash ブロックにする

## 完了条件

- [x] 配布対象 skill の相互参照が claude-code と codex の両方の配置で解決する
- [x] 配布対象 skill の本文に `.claude/skills/` 配下への SKILL.md 参照、`AskUserQuestion`、`/coff-*` 記法が残っていない
- [x] coff-init がどちらの配置からでも兄弟 skill の導入と規約追記を完了する
- [x] coff-issue-list が両 agent で引数付きで動く
- [x] `test/static.sh` が上 2 条件を決定的に検査し、変更前の配布物では失敗し、修正後に通る
- [x] `test/e2e.sh` が両 CLI で coff-issue-done を実行し `status: done` を確認する
- [x] README に codex での導入手順とテストの実行方法がある

## 実装メモ

### 実装詳細

- `.coff/src/coff-detail-issue.skill.md`：先頭コメントと「直接呼び出し」節の `.claude/...` と `/coff-detail-issue` を記法非依存に。
- `.coff/src/coff-issue-create.skill.md` / `coff-issue-polish.skill.md` / `coff-issue-done.skill.md`：手順 1 の参照を `../coff-detail-issue/SKILL.md` へ。polish は「fork」但し書きと codex-delegate 参照の条件付け。
- `.coff/src/coff-compile.skill.md`：`AskUserQuestion` / `multiSelect` を機能記述へ。例示を引数だけにして接頭辞の注記。description の `.claude/` を「既定の配置先」へ。
- `.coff/src/coff-issue-list.skill.md`：`!` フェンスを bash ブロックに変え、実行指示を 1 文追加。
- `.coff/src/coff-init.skill.md`：配置場所による agent 判別、`--agent` の可変化、規約ファイルの選択、規約文と出口基準の `.claude/` と `/coff-compile` を記法非依存へ。規約文のビルド指示は claude-code なら既定出力、codex なら `--out .agents`（実体出力）。兄弟導入にネットワークが要る旨を注記。
- `README.md`：codex 向け導入コマンド（`--agent codex`、`$coff-init`）とテストの実行方法。
- `test/static.sh`（新規）、`test/e2e.sh`（新規）。

後で効く制約:

- 相対参照の基準は cwd ではなく「その SKILL.md があるディレクトリ」。本文にそう明記する（cwd 基準で解決されると失敗する）。
- coff-init の agent 判別は、agent が skill 読み込み時に提示する自身の SKILL.md のパス（claude は「Base directory for this skill」、codex は skill 一覧のパス）が `.claude/skills/` と `.agents/skills/` のどちらの配下かで行い、user scope でも同じ。判別できなければユーザーに聞く。兄弟導入の `--scope` は既定（project）のまま。
- `gh skill install --scope project` の配置は claude-code が `.claude/skills/`、codex が `.agents/skills/`（gh 2.95.0 で実測）。テストは作業ツリーの配布物を検査するので `--from-local <repo>` で導入する。
- `claude -p` のスラッシュ呼び出しは、モデルの turn を要する skill なら動く。埋め込みだけの skill は 0 turn・空出力。書き込みを伴う skill には `--allowedTools 'Skill,Bash,Read,Edit,Write'` を付ける。
- codex の非対話実行は `codex exec --skip-git-repo-check '$name 引数'`。書き込みを伴う skill には `--sandbox workspace-write` が要る。`workspace-write` のサンドボックスはネットワークを遮断し、`.agents/` を読み取り専用にするので、coff-init の兄弟導入は対話での承認か `--sandbox danger-full-access` が要る（`--from-local` でも `.agents/` への書き込みで止まる。実測）。

### 完了条件の確認手段

1. `test/static.sh` を実行し PASS を見る（検査内容はスクリプト冒頭のコメント）。
2. 同じスクリプトの禁止パターン検査で確認する。
3. coff-init 本文の導入コマンドを `--from-local <repo>` に差し替えた一時コピーを、両 agent の一時 repo に置き、各 CLI で coff-init を実行する。兄弟 skill が同じ配置に揃い、claude-code では CLAUDE.md、codex では AGENTS.md に coff 節が 1 回だけ入ることを見る（再実行で重複しないことも見る）。`--from-local` ならネットワークは要らないが、codex は `.agents/` への書き込みのため `--sandbox danger-full-access` で実行する。
4. 一時 repo に issue を 1 件置き、各 CLI で coff-issue-list を `done` 引数で実行して 0 件が返ることを見る。
5. 変更前の配布物（変更前のコミットの worktree に `test/static.sh` をコピーして実行）で失敗し、ブランチで成功することを見る。
6. `test/e2e.sh` を実行し、両 agent が PASS になることを見る。
7. README を目視する。

### 調査記録

- codex の skill 発見は `$CWD/.agents/skills`、`$REPO_ROOT/.agents/skills`、`$HOME/.agents/skills`、`/etc/codex/skills`。明示呼び出しは `$name` か `/skills`。出典: https://developers.openai.com/codex/skills
- codex のサブエージェントは `codex features list` で `multi_agent` が stable / 有効（codex-cli 0.153.4）。ツールは `spawn_agent` など。
- codex の規約ファイルは AGENTS.md / AGENTS.override.md。CLAUDE.md は `project_doc_fallback_filenames` を設定した場合のみ読む。出典: https://developers.openai.com/codex/guides/agents-md
- Claude Code 2.1.272 の skill 発見は `.claude/skills/` と `~/.claude/skills/` のみ。`.agents/skills/` 対応要望は未対応のまま open。出典: https://code.claude.com/docs/en/skills 、https://github.com/anthropics/claude-code/issues/31005
- codex にセッションを識別する安定した環境変数は無い（`CODEX_SESSION_ID` は要望段階）。出典: https://github.com/openai/codex/issues/8923
- 試行（2026-09-15、一時 repo に 3 skill を導入）: codex は `$coff-issue-list` と `$coff-issue-list done` を正しく返し、相対参照に書き換えた coff-issue-done で `.agents/skills/coff-detail-issue/SKILL.md` を読んで `status: done` にした。claude は `-p '/coff-issue-done <path>'` で同様に `status: done` にした。`-p '/coff-issue-list'` は空出力で、自然文で指名すると表が返った。
- 確認（2026-09-15、実装後）: coff-init を導入コマンドの `--from-local` 差し替えで両 CLI で 2 回ずつ実行し、兄弟 9 skill が同じ配置に揃い、claude-code は CLAUDE.md、codex は AGENTS.md に coff 節が 1 つだけ入った。codex は `workspace-write` では `.agents/` への書き込みで止まり、`--sandbox danger-full-access` で通った。coff-issue-list の `done` 引数は両 CLI で 0 件を返した。`test/static.sh` は変更前のコミットの worktree で FAIL、ブランチで PASS。`test/e2e.sh` は両 CLI で PASS。

### 参考

- issue/2026/07/1921-gh-skill-installable.md：配布レイアウトと `--agent` stub の決定。他 agent 配布時の参照切れを先送りした記録。
- issue/2026/07/1518-polish-implementer-sim.md：ネイティブサブエージェントを既定にした決定。
- .coff/src/coff-argument-gap-edit.skill.md：相対参照の先例。
