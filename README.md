## COFF

skill as a code/token save/care giver

## インストール

GitHub CLI の agent skills 対応版（`gh skill` が使えること）が前提。

```bash
gh skill install Fuyutsubaki/coff coff-init --agent claude-code
```

導入先のリポジトリで Claude Code から `/coff-init` を実行すると、残りの coff スキルの一括導入と issue 運用の初期化が行われる。

個別に選んで入れる場合は、対話選択の `gh skill install Fuyutsubaki/coff` も使える。

### グローバル（ユーザースコープ）に入れる場合

```bash
gh skill install Fuyutsubaki/coff --all --agent claude-code --scope user
```

この場合、導入先のリポジトリでは `/coff-init` ではなく `/coff-repo-init` を実行する。スキルの導入は行わず、issue 運用の初期化（`issue/` 作成、CLAUDE.md への規約追記）だけを行う。

## ライセンス

MIT（`LICENSE` を参照）。
