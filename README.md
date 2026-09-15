## COFF

skill as a code/token save/care giver

## インストール

GitHub CLI の agent skills 対応版（`gh skill` が使えること）が前提。

```bash
gh skill install Fuyutsubaki/coff coff-init --agent claude-code   # Claude Code
gh skill install Fuyutsubaki/coff coff-init --agent codex         # Codex
```

導入先のリポジトリで coff-init skill を実行すると（Claude Code は `/coff-init`、Codex は `$coff-init`）、残りの coff スキルの一括導入と issue 運用の初期化が行われる。

個別に選んで入れる場合は、対話選択の `gh skill install Fuyutsubaki/coff` も使える。

## テスト

```bash
test/static.sh   # 配布物を両 agent の配置に導入し、相互参照の解決と claude 固有の記述の不在を検査する
test/e2e.sh      # claude と codex を非対話で起動し、coff-issue-done が完走することを確認する（両 CLI の認証が要る）
```

## ライセンス

MIT（`LICENSE` を参照）。
