---
name: coff-init
description: Set up the coff skill suite in a target repo. Bulk-installs the missing coff skills and initializes the issue workflow (create `issue/`, add the conventions section to CLAUDE.md).
license: MIT
---

## Procedure

1. Prerequisites: confirm the current directory is a git repository, the `gh` CLI is available, and `gh skill --help` succeeds (an agent-skills-capable version). If anything is missing, report what's lacking and stop.
2. Install sibling skills: for each coff skill whose directory does not exist under `.claude/skills/`, install it one at a time with the command below. Judge "missing" by directory existence only; do not compare versions.

   ```bash
   # 対象: coff-detail-issue coff-issue-create coff-issue-polish coff-issue-done
   #       coff-compile coff-japanese-tech-writing coff-argument-gap-edit
   #       coff-review-diff-code coff-adopt-lessons coff-log-investigate
   gh skill install Fuyutsubaki/coff <name> --agent claude-code
   ```

   Do not omit `--agent claude-code`.
3. Initialize:
   - Create the `issue/` directory if absent.
   - Add the coff conventions section to CLAUDE.md. Create the file if absent. If the heading `## coff` already exists, do nothing. Leave existing content untouched and append the following section verbatim at the end:

     ```markdown
     ## coff
     - `.claude/` 配下の coff 成果物（skills など）は手で編集しない。変更は `.coff/src/` のソースを編集し、`/coff-compile` でビルドする。
     - issue 運用の入口は coff-issue-create skill。流れは create → polish → 実装 → done。
     ```
4. Report: report the installed skills and the initialization results. Also briefly introduce the issue workflow (create → polish → implement → done), and note that the `.coff/src/` conventions with `/coff-compile` are available for source-managing one's own skills.

## Exit bar

- The coff skill suite is present under `.claude/skills/`, and `issue/` and the CLAUDE.md coff section exist.
<!--{"src":".coff/src/coff-init.skill.md","md5":"97077975ea76334f4bea77c5b16e21b7"} -->
