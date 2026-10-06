---
name: coff-dullmify
description: Convert a skill source into a workflow in the given language plus a thin skill. `<source> -o <outdir> --lang <ruby|cpp>`; all arguments are required.
license: MIT
allowed-tools: Write Bash(sh ${CLAUDE_SKILL_DIR}/assemble.sh *)
---

Parse the arguments as `<source> -o <outdir> --lang <lang>`. If any is missing, duplicated, or extra, show the usage and stop. `<outdir>` must not exist or must be an empty directory. Assume the source's frontmatter values contain no `---`.

Relative to the directory containing this SKILL.md, check with a file read whether `langs/<lang>/GUIDE.md` exists. If not, list the supported languages from `langs/*/GUIDE.md` and stop. Read the source, the chosen GUIDE, and `review.md` each with a file read. They are not pre-approved, so do not read them with shell commands such as `cd`, `cat`, or `ls`.

Do the following round at most 3 times.

1. Turn the source's control flow into a workflow using the GUIDE's API. Limit questions to judgments only an LLM can make, and cause side effects through the helper functions. For each numbered step of the source (each paragraph if there are no numbers), add a comment with its section heading and step number in the same language as the source.
2. Write the whole workflow, under the name the GUIDE specifies, into `<outdir>/scripts/` with Write. When fixing it, rewrite the whole file with Write as well. Only Write is pre-approved, so Edit, `sed`, and heredocs stop at an approval prompt. Write no other files.
3. Resolve the absolute path of `assemble.sh` in the same directory as this SKILL.md and call `sh <absolute path>/assemble.sh <lang> <source> <outdir>` as a standalone command. If the syntax check fails, fix it in the next round using only that output. Do not use other checking commands.
4. Once assembly passes, fill the full text of the source, the workflow, and the GUIDE into the `review.md` template and hand it to a new subagent that does not inherit the conversation. Use Agent in Claude Code and `spawn_agent` in Codex. Have the reviewer judge only from what was passed. If the first line is `合格`, finish. If it is `不合格`, fix it in the next round using only the findings.

Do all 3 rounds even if the cause looks environmental, and do not bypass the check or the review. If none of the 3 rounds passes, call `sh <absolute path>/assemble.sh --discard <outdir>` as a standalone command to remove `<outdir>` entirely, and report the failure reason.
<!--{"src":".coff/src/coff-dullmify.skill/SKILL.md","md5":"b6be97a687dea0862cc9dbf642541af6"} -->
