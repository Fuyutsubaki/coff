## workflow の実行

`perl ${CLAUDE_SKILL_DIR}/scripts/run.pl start $ARGUMENTS` を実行し、JSON 応答を読む。

応答に `ask` があれば、`kind` と `topic` に従って答えを作り、答えだけを標準入力から `perl ${CLAUDE_SKILL_DIR}/scripts/run.pl resume <run> <index>` へ渡す。
答えは single-quoted heredoc でそのまま渡す。
`done: true` まで繰り返す。

会話のコンテキストを失ったら `status <run>` で未回答の問いを取得する。
run の終了には `cancel <run>`、7 日より古い run の削除には `gc` を使う。

## topic ごとの判断

