---
status: done
---
# coff-compile の既定出力先を claude 固定にせず、実行中の agent の配置先にする

coff-compile は既定の出力ルートが `.claude/` に固定され、codex 向けは `.claude/` の正本を指す参照 stub しか出せない。
codex 単独の環境では引数なしのビルドが発見されない場所に出るため、claude と codex で扱いが非対称になっている。
既定を実行中の agent の配置先にし、両 agent を同じ規則で扱えるようにしたい。

## 目的

coff-compile は agent 横断で配布する skill だが、出力先の既定が claude-code の配置（`.claude/`）に固定されている。
解けた状態は、claude-code と codex のどちらから引数なしで実行しても、その agent が発見する場所に実体が出て、他 agent 向けの出力も同じ規則で導出できることである。

output style と agent 型は claude-code 固有の種別なので、codex の配置先に出さない非対称は残す。
codex 以外の agent への対応は扱わない。

## 現状

- `.coff/src/coff-compile.skill.md` の入出力表、`--out` の既定、手順 1 の `dsts` 導出は、いずれも `.claude/` を直書きしている。
- agent プリセット表は `claude-code` を「`.claude/` に実体」、`codex` を「`.agents/` に参照」と固定し、参照 stub の本文は `../../../.claude/skills/<name>/SKILL.md` を指す。
  codex 単独の環境では `.claude/` が無く、この stub は解決しない。
- issue/2026/09/1515-drop-claude-dependency.md は、この非対称を承知で「codex 単独では `--out .agents` を使う」と coff-init の規約文に書いて回避した。
  coff-init 自身は配置場所で agent を判別しており、同じ判別を coff-compile が持てば回避は不要になる。
- coff repo 自身のビルド入口 `compile` skill（非配布）は、`.claude/skills/` を正本として `skills/` にミラーする前提で書かれている。

## 設計方針

実行中の agent を coff-compile 自身の SKILL.md の配置パスで判別し、そのルートを既定の出力ルートにする。
判別は coff-init 手順 2 と同じ規則（`.claude/skills/` 配下なら claude-code、`.agents/skills/` 配下なら codex、判別できなければユーザーに聞く）を使う。

- 入出力表・`--out` の既定・`dsts` 導出は、ルートを変数として書く。
- agent プリセット表は「agent → 出力ルート」だけを持たせ、実体か参照かは表から外して規則にする。
  実行中 agent のルートには実体を、`--agent` で明示した他 agent のルートには実行中 agent の正本を指す参照 stub を出す。これで実行中の agent がどちらでも同じ導出になる。
- 参照 stub の本文は、stub を置くディレクトリから正本への相対パスとして計算する（`../` の数を固定しない）。
  正本が存在しないか、それ自体が参照 stub なら参照を書かずエラーにする（どこにも実体のない相互参照を作らないため）。
  agent のルートはリポジトリ直下の 1 階層なので、skill なら `../../../<正本ルート>/skills/<name>/SKILL.md` になる。
- 正本と参照の区別は skill 型だけの話で、正本は実行中 agent のルートに固定する。`--out` は出力ルートを置き換えるだけで（現行どおり）正本を動かさず、参照出力は正本に実体が無ければエラー。
- claude 固有の種別（outputstyle / agent 型）には正本／参照の区別を持たせず、`.claude/` に置く 1 つを常に実体とする。
  agent から導いたルートに `.claude/` が入るときだけ出し（codex 実行時は `--agent claude-code` を渡したときに限る）、入らなければレポートにも出さない。`--out` で明示されたルートは指定どおり全種別を出す（現行どおり）。
- skip 判定を md5 一致だけにせず、出力先の本文も見る。参照を出すべき先は期待する参照行と文字列一致すること、実体を出すべき先は参照行の形でないことを条件にする。
  実体の本文は英訳を通るので事前に再現できず、一致比較の対象にしない。
- 判別できず、対話で聞けないときは、既定のルートを推測せずエラーとして中断する。
- coff-init の規約文から `<build>`（codex のとき `--out .agents`）の置換をやめる。既定で codex の配置先に実体が出るので、但し書きが要らなくなる。

却下した代替案:

- 出力ルートを設定ファイルや環境変数で持つ — coff-init の配置パス判別と二重管理になり、食い違いの種になる。codex には agent を識別できる安定した環境変数も無い。
- 既定で両方のルートに出す — codex を使わない repo に `.agents/` ができる。増やすのは明示の `--agent` のときだけにする。
- `.claude/` があるときはそちらを正本に固定する — 両方のルートがある repo では codex からの引数なし実行が `.claude/` に出たままで、目的の非対称が残る。

対象外: coff repo 自身の `compile` ラッパーと `skills/` ミラー（coff repo は claude-code から実行するので既定の判別結果が `.claude/` になり、ミラー元は変わらない）。自動テストの追加。

## 決めたこと

- 自動テストは足さず、完了条件の確認は手動手順で行う

## 完了条件

- [x] coff-compile を引数なしで実行すると、claude-code では `.claude/`、codex では `.agents/` に実体が出る
- [x] `--agent <他 agent>` で出る参照 stub が、実行中 agent の正本を指し、その相対パスが解決する
- [x] 実体が出ている出力先に参照を出すとき、md5 が一致していても skip されずに書き換わる
- [x] coff-compile の本文と description が、既定の出力ルートを `.claude/` に固定していない
- [x] coff-init の規約文が、codex の配置でも `--out` の但し書きなしでビルド指示として成立する

## 実装メモ

### 実装詳細

- `.coff/src/coff-compile.skill.md`：実行中 agent の判別手順を追加。入出力表・`--out` の既定・手順 1 の `dsts` 導出を出力ルート変数に。agent プリセット表を「agent → 出力ルート」に変え、実体／参照の決まり方を規則として書く。skip 判定に出力先本文の照合を加える。frontmatter の description の既定ルート表記を直す。
- `.coff/src/coff-init.skill.md`：手順 4 の `<build>` 置換指示・その理由コメント・規約節テンプレート内のプレースホルダを削除する。

後で効く制約:

- 実体と参照はソースが同じなら md5 も同じになる。参照先だけが違う stub も同様。skip 判定を md5 だけにすると、この 2 つの切り替えを取りこぼす。
- 判別は配置パスが `.claude/skills/` と `.agents/skills/` のどちらの配下かだけを見る。user scope（`~/.claude/skills/` など）に導入されていても、出力ルートはカレントリポジトリ直下。
- 確認手段の `--from-local` が読むのは配布ミラー `skills/` なので、確認はビルドとミラー同期を済ませてから行う。
- codex の `workspace-write` サンドボックスは `.agents/` を読み取り専用にする。codex から引数なしでビルドするには、対話で承認するか `--sandbox danger-full-access` が要る。
- 両 agent が同じ repo でビルドする場合、`--agent` を渡さなかった側のルートは更新されずに古くなる（現行と同じ）。
- 成果物（`.claude/skills/` と `skills/`）は手で編集せず、ソースを直して compile skill でビルドする。
- 配布物を変えるので、ビルド後に `test/static.sh` を一度通す。

### 完了条件の確認手段

1. 一時 repo（git init 済み）に lint 候補の出ない最小の `.coff/src/foo.skill.md` を 1 件置き、作業ツリーの coff-compile を `gh skill install --from-local <repo> coff-compile --agent <agent> --scope project` で両 agent の配置に導入する。同じ repo で各 CLI から coff-compile を引数なしで実行し、claude-code では `.claude/skills/foo/SKILL.md`、codex では `.agents/skills/foo/SKILL.md` に本文付きの実体が出ることを見る。codex は上記サンドボックスの制約があるので `--sandbox danger-full-access` で実行する。
2. 同じ repo で claude-code から `--agent codex` を実行する。次に codex から引数なしで実行して `.agents/` を実体に戻したうえで、codex から `--agent claude-code` を実行する（正本が stub のままでは参照出力がエラーになる）。それぞれ出た stub の参照行が実行中 agent のルートを指し、そのパスが stub のディレクトリから `test -e` で解決することを見る。
3. 手順 2 の 1 つ目の実行を見る。`.agents/skills/foo/SKILL.md` は手順 1 で実体になっていて md5 も一致しているのに skip されず、レポートに `compiled` が出て本文が stub に置き換わっていることを確かめる。
4. `grep -n '\.claude' .coff/src/coff-compile.skill.md` を実行し、既定の出力ルートを `.claude/` と書いている行が無いことを見る。残ってよいのは agent 判別規則・プリセット表の claude-code 行・claude 固有種別の置き場の 3 種のみ。
5. coff-init 本文の規約節テンプレートを読み、`<build>` の置換指示とプレースホルダが消えていること、残った文面が手順 1 で成立した引数なしのビルドを指していることを見る。

### 参考

- issue/2026/09/1515-drop-claude-dependency.md：coff-init の agent 判別と、codex 単独では `--out .agents` を使うという回避の記録。codex のサンドボックス制約の実測もここにある。
- issue/2026/07/1921-gh-skill-installable.md：配布レイアウトと `--agent` stub の決定。
- .coff/src/coff-init.skill.md：配置パスによる agent 判別の先例（手順 2）。
