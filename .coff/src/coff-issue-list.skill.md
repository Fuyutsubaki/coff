---
name: coff-issue-list
description: `issue/` の issue を一覧する。引数は `open`（既定）| `done` | `all`。状態、パス、タイトル、要約の 1 行目を表で出す。
license: MIT
coff-dist: true
allowed-tools: Bash(awk *)
---

<!--
一覧は LLM の手順にせず、埋め込みコマンド（`!` バッククォート）で bash を実行するだけにする（issue/2026/09/1413-issue-template-for-human-reader.md の判断）。埋め込みコマンドは permission が allow でないと起動が中断されるため、allowed-tools で awk を前もって許可し、パイプやループを避けて awk 1 コマンドに収めている。`issue/*/*/*.md` はシェルのグロブ展開でパス順（年月日時順）に並ぶ。状態の解釈（frontmatter または status が無ければ open）は coff-detail-issue の状態仕様に従う。要約はタイトルより後で最初に現れる、見出しでも空行でもない行。埋め込みコマンドでは `$0` `$1` が N 番目の引数に置換されるため、awk の `$0` は `$(0)` と書く。一覧ファイル（README）を置く案は陳腐化するため却下した。
-->

以下は `issue/` の一覧（引数 `$ARGUMENTS`。空なら `open`）。この表をそのまま提示する。issue ファイルは変更しない。

!`awk -v want="$ARGUMENTS" 'BEGIN{if(want=="")want="open";print "| 状態 | パス | タイトル | 要約 |";print "|---|---|---|---|"} function flush(){ if(f!=""&&(want=="all"||want==st)){gsub(/\|/,"\\|",t);gsub(/\|/,"\\|",s);printf "| %s | %s | %s | %s |\n",st,f,t,s;n++} } FNR==1{flush();f=FILENAME;st="open";t="";s="";fm=($(0)=="---")} fm{ if(FNR>1&&$(0)=="---"){fm=0;next} if(match($(0),/^status:[ \t]*[a-z]+/)){st=substr($(0),RSTART,RLENGTH);sub(/^status:[ \t]*/,"",st)} next } t==""&&/^# /{t=substr($(0),3);next} t!=""&&s==""&&NF&&!/^#/{s=$(0)} END{flush();printf "\n%d 件\n",n+0}' issue/*/*/*.md 2>/dev/null`
