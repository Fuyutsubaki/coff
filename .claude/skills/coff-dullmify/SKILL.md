---
name: coff-dullmify
description: Convert a skill source into a workflow in the given language plus a thin skill. `/coff-dullmify <source> -o <outdir> --lang <ruby|cpp>`.
license: MIT
allowed-tools: Write Bash(sh ${CLAUDE_SKILL_DIR}/assemble.sh *)
---

# coff-dullmify

Read the skill source and move its procedural control into a workflow in the given language. Leave only judgments that only an LLM can make as questions.

Arguments take the form `<source> -o <outdir> --lang <lang>`; all three of `<source>`, `<outdir>`, `<lang>` are required. If any is missing, show this form and stop. Resolve `source` and `outdir` to absolute paths. Assume the source's frontmatter values contain no `---`; do not check it here.

Refer to bundled files relative to the directory containing this SKILL.md. If `langs/<lang>/GUIDE.md` does not exist, list the supported languages from `langs/*/GUIDE.md` and exit before generating. Read the target language's `GUIDE.md` for its API, entry point, workflow filename, and rules. Read `review.md` for the review method and reply format. Read the source, the GUIDE, and `review.md` with the file-reading tool, not with shell commands.

Steps 1–5 below make one round; do at most 3 rounds. Count rounds by calls to `assemble.sh <lang> …`; after 3 calls, do not make a 4th.

1. Map each step of the source onto a sequential workflow. Limit questions to judgments only an LLM can make; do file operations and command execution through the GUIDE's helper functions. On the code for each item of the source's numbered procedure (each paragraph if there is none), add a comment with the section heading and step number, in the same language as the source. If the previous round failed, fix its syntax error or review findings.
2. The LLM writes only the workflow body. Write it into `<outdir>/scripts/` under the filename the GUIDE specifies, using the file-writing tool. Do not write it via heredoc or the shell. Do not touch other files in `<outdir>`.
3. Resolve the absolute path of `assemble.sh` in the same directory as this SKILL.md, and call only `sh <absolute path>/assemble.sh <lang> <source> <outdir>` as a standalone command. Do not substitute or bypass the syntax check by other means. On failure, read only the reason `assemble.sh` printed and go to the next round. Do not run other commands to investigate the cause.
4. When assembly succeeds, mechanically insert the full contents of the source, workflow, and GUIDE into the `review.md` template. Spawn a new subagent that does not inherit the conversation and have it review, passing only the filled-in prompt. Use the Agent tool in Claude Code, `spawn_agent` in Codex. Do not substitute yourself, and do not let the subagent read files.
5. If the review's first line is `合格`, finish. If it is `不合格` or violates the format, read the findings and go to the next round. Do not bypass the review.

If all 3 rounds fail, call `sh <absolute path>/assemble.sh --discard <outdir>` as a standalone command, report the last failure reason verbatim, and stop. Leave neither `<outdir>/SKILL.md` nor `<outdir>/scripts/`.
<!--{"src":".coff/src/coff-dullmify.skill/SKILL.md","md5":"c1151ba1c363eb8410ba754d3d344c02"} -->
