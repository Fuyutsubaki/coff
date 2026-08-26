---
name: coff-log-investigate
description: Investigate the cause of a problem from Claude Code session logs and report in the form 事象・経緯・原因・教訓候補. No fixes. Args are one sentence stating what the problem was, plus optionally a session ID or a datetime.
license: MIT
---

## Procedure

1. Determine the target log. Logs live per project at `~/.claude/projects/<cwd with non-alphanumerics replaced by ->/<session-id>.jsonl`.

   ```bash
   dir=~/.claude/projects/"$(printf '%s' "$PWD" | tr -c 'a-zA-Z0-9' '-')"
   ls -t "$dir"/*.jsonl | head -5
   ```

   - No spec given: pick the 2nd in modification-time order.
   - Session ID given: that file.
   - Datetime given: treat it as JST, convert to UTC (the log's `timestamp` is UTC ISO format), and pick the log whose time range contains it.
   - Multiple candidates remain: for each log, list the beginning of the first user input that is string-typed and does not start with a tag (`<command-message>` etc.), and confirm with one question. If only tagged inputs exist, use the content of `<command-args>`.
2. Delegate the investigation to a subagent. The main session does not read the log body. Launch the Agent tool's Explore type (has Bash, no Edit / Write). Pass only: the log path, the one-sentence problem, the timeline summary script below, and the report form. Key instructions: read-only, change no files, separate inference from evidence, quotes at most a few lines each.
3. The subagent prints a timeline with the script, surveys it, and locates the region around the problem.

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

   `thinking` is not shown in the timeline. Only for the located region, use the line numbers (`L<n>`) to fetch the original JSON with `sed -n '<n>p' <ログパス>` and read `thinking` and `tool_result` in full.
4. When the problem appears to have happened inside a subagent, also read `<session-id>/subagents/agent-*.jsonl` the same way (conversation rows have the same format as the main log). Identify which subagent via the adjacent `agent-*.meta.json`'s `description` and the timestamps.
5. The subagent reports in the four-section form below; the main session presents it as-is. No fixing, no adopting. To adopt a lesson, point to the coff-adopt-lessons skill.
   - 事象: what happened
   - 経緯: the sequence, with log timestamps
   - 原因: which judgment went wrong, with quotes of the utterances or thinking as evidence
   - 教訓候補: one sentence that could become a norm; 「なし」 if none

## Notes

- When the sequence has an unnatural jump (signs of context compaction, etc.), say so in the report.
- If the problem happened in the current session, the default selection cannot pick it up; ask for an explicit session ID.
- To run in a separate process, delegate to the codex-delegate skill (only if installed).
<!--{"src":".coff/src/coff-log-investigate.skill.md","md5":"320875a1a9c3d2486e4b07eef925d3cd"} -->
