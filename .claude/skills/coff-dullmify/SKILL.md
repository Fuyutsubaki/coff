---
name: coff-dullmify
description: Convert a skill source into a program in the given language plus a thin skill that calls it. `/coff-dullmify <source> -o <outdir> --lang <ruby|cpp>`.
license: MIT
allowed-tools: Write Bash(sh ${CLAUDE_SKILL_DIR}/assemble.sh *)
---

Let `<dir>` be the directory containing this SKILL.md. Bundled files are referred to relative to `<dir>`.

## Arguments

`<source> -o <outdir> --lang <lang>`. All three are required. If any is missing, show this form and stop.

- `<source>`: the skill source to convert. Markdown with frontmatter. Do not put `---` inside a frontmatter value.
- `<outdir>`: the directory to write the thin skill into. Its `SKILL.md` and `scripts/` are replaced. Other files there are left alone.
- `<lang>`: a directory name under `<dir>/langs/`. If `<dir>/langs/<lang>/GUIDE.md` does not exist, list `<dir>/langs/` and stop.

## Procedure

1. Read `<source>` and `<dir>/langs/<lang>/GUIDE.md`.
2. Write the workflow. Write only the workflow body; `assemble.sh` bundles the runtime and the launcher.
   - Put all control of the source's procedure (branching, loops, file and command handling, answer validation) in the program. Make an `ask` only for judgments only an LLM can make (interpreting text, extraction, classification, confirming with the user).
   - Say in the prompt what to answer and how. When the answer must have a format, validate it in the workflow and ask again with the reason when it is malformed. Decide the retry limit in the workflow.
   - Never have the prompt ask the LLM to change files or run commands. Cause side effects through the helpers. A question that needs a tool to answer (confirming with the user, looking at a file) may say so in the prompt.
   - All interaction with the outside world goes through the helpers in the GUIDE. Any input or output that bypasses them is a bug.
   - For each step of the source (one item of a numbered procedure, or one paragraph when there is none), write a comment with the section heading and the step number, in the source's language.
   - Return the report as a string in the form the source specifies.
3. Write the workflow with the file-writing tool to `<outdir>/scripts/<file name given in the GUIDE>`. Do not pass it through a Bash heredoc.
4. Check and write out with `assemble.sh`. Call it by the absolute path of `<dir>` as a single command, passing the path of the file written in step 3.

   ```
   sh <dir>/assemble.sh <lang> <source> <outdir> <outdir>/scripts/<file name>
   ```

   If the check fails, `assemble.sh` prints the reasons, deletes the file from step 3 as well, and leaves nothing in `<outdir>`. Read the reasons, fix the workflow, and repeat from step 3. Generation and check together are limited to 3 attempts. If the third also fails, report failure with the last reasons and stop. Do not bypass the check: do not call the compiler or the checker by other means, and do not make a fix that merely rewrites a rejected API into another spelling of the same behavior.
5. Report the output of `assemble.sh` (the list of files written).
<!--{"src":".coff/src/coff-dullmify.skill/SKILL.md","md5":"2bd74bf10a0f7afc422986291ac83fcd"} -->
