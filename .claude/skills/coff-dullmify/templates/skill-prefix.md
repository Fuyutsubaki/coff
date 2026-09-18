## workflow の実行

`perl ${CLAUDE_SKILL_DIR}/scripts/workflow.pl start $ARGUMENTS` を実行し、JSON 応答を読む。

応答に `ask` があれば、`topic` に従って答えを作り、答えだけを標準入力から `perl ${CLAUDE_SKILL_DIR}/scripts/workflow.pl resume <run> <index>` へ渡す。
答えは single-quoted heredoc でそのまま渡す。
`done: true` まで繰り返す。

## topic ごとの判断

