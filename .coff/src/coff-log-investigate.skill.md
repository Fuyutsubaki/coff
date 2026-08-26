---
name: coff-log-investigate
description: Claude Code のセッションログから問題の原因を調査し、事象・経緯・原因・教訓候補の型で報告する。修正はしない。引数は「何が問題だったか」の一文と、任意でセッション ID か日時。
license: MIT
coff-dist: true
---

<!--
ログ読解を subagent に委譲して本体のコンテキストを守る構成。設計判断は issue/2026/08/2322-log-investigate-skill.md。ログ形式は Claude Code の内部仕様（2026-08 時点）で、壊れたらこの skill 側を直す。
-->

## 手順

1. 対象ログを確定する。ログはプロジェクトごとに `~/.claude/projects/<cwd の英数字以外を - に置換した名前>/<session-id>.jsonl` にある。

   ```bash
   dir=~/.claude/projects/"$(printf '%s' "$PWD" | tr -c 'a-zA-Z0-9' '-')"
   ls -t "$dir"/*.jsonl | head -5
   ```

   - 指定なし: 更新時刻順で 2 番目を選ぶ。 <!-- 最新はこの呼び出し自体が書き込まれた現在のセッション -->
   - セッション ID 指定: そのファイル。
   - 日時指定: JST として受け取り UTC に直し（ログの `timestamp` は UTC の ISO 形式）、その時刻を範囲に含むログを選ぶ。
   - 候補が複数残るとき: 各ログについて、文字列型でタグ（`<command-message>` など）で始まらない最初のユーザ入力の冒頭を並べ、一問で確かめる。タグ付きしか無ければ `<command-args>` の中身を使う。
2. 調査を subagent に委譲する。本体ではログ本文を読まない。起動は Agent ツールの Explore 型（Bash あり、Edit / Write なし）。渡すのは、ログのパス・問題の一文・下のタイムライン要約スクリプト・報告の型だけ。指示の要点: 読み取り専用でファイルを変更しない、推測と根拠を分けて書く、引用は 1 箇所あたり数行まで。
3. subagent はスクリプトでタイムラインを出し、俯瞰して問題の前後を特定する。

   ```bash
   python3 - <ログパス> <<'EOF'
   import json,sys,datetime
   JST=datetime.timezone(datetime.timedelta(hours=9))
   def head(s,n): return ' '.join(str(s).split())[:n]
   for i,line in enumerate(open(sys.argv[1]),1):
       try: d=json.loads(line)
       except Exception: continue
       if d.get('type') not in ('user','assistant'): continue
       try: t=datetime.datetime.fromisoformat(d['timestamp'].replace('Z','+00:00')).astimezone(JST).strftime('%m-%d %H:%M:%S')
       except Exception: t=d.get('timestamp','?')
       c=d.get('message',{}).get('content')
       if isinstance(c,str): print(f"L{i} {t} {d['type']}: {head(c,200)}"); continue
       for b in c or []:
           k=b.get('type')
           if k=='text': print(f"L{i} {t} {d['type']} text: {head(b.get('text',''),200)}")
           elif k=='tool_use': print(f"L{i} {t} {d['type']} tool {b.get('name')}: {head(json.dumps(b.get('input',{}),ensure_ascii=False),100)}")
           elif k=='tool_result':
               cc=b.get('content')
               if isinstance(cc,list): cc=' '.join(x.get('text','') for x in cc if isinstance(x,dict))
               print(f"L{i} {t} {d['type']} result: {head(cc,100)}")
   EOF
   ```

   `thinking` はタイムラインに出さない。特定した範囲だけ、行番号（`L<n>`）を使って `sed -n '<n>p' <ログパス>` で元 JSON を取り、`thinking` と `tool_result` の全文を読む。
4. 問題が subagent 内で起きたと見えるときは、`<session-id>/subagents/agent-*.jsonl`（会話行の形式は本体と同じ）も同様に読む。どの subagent かは並びの `agent-*.meta.json` の `description` と時刻で突き合わせる。
5. subagent は次の 4 節の型で報告し、本体はそれをそのまま提示する。修正や採用はしない。教訓を採用するなら coff-adopt-lessons skill を案内する。
   - 事象: 何が起きたか
   - 経緯: 時系列。ログの時刻つき
   - 原因: 判断のどこが誤ったか。根拠となる発話や thinking の引用つき
   - 教訓候補: 規範に落とせそうな一文。なければ「なし」

## 注意

- 経緯に不自然な飛びがあるとき（コンテキスト圧縮の痕跡など）は、その旨を報告に書く。
- 調査したい問題が現在のセッションで起きた場合、既定の選択では拾えない。セッション ID の明示を求める。
- 別プロセスで実行したいときは、codex-delegate skill（導入されている場合のみ）に委譲する。
