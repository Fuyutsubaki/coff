---
status: open
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
