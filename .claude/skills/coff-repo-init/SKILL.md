---
name: coff-repo-init
description: Initialize the coff issue workflow in a target repo (create `issue/`, add the conventions section to CLAUDE.md). Installs no skills. The entry point when the coff skills are installed at user scope (`~/.claude/skills/`).
license: MIT
---

## Procedure

1. Prerequisites: confirm the current directory is a git repository. If not, report it and stop.
2. Initialize:
   - Create the `issue/` directory if absent.
   - Add the coff conventions section to CLAUDE.md. Create the file if absent. If the heading `## coff` already exists, do nothing. Leave existing content untouched and append the following section verbatim at the end:

     ```markdown
     ## coff
     - `.claude/` 配下の coff 成果物（skills など）は手で編集しない。変更は `.coff/src/` のソースを編集し、`/coff-compile` でビルドする。
     - issue 運用の入口は coff-issue-create skill。流れは create → polish → 実装 → done。一覧は coff-issue-list skill。
     ```
3. Report: report the initialization results. Also briefly introduce the issue workflow (create → polish → implement → done).

## Exit bar

- `issue/` and the CLAUDE.md coff section exist.
<!--{"src":".coff/src/coff-repo-init.skill.md","md5":"5e053e534b49d02527732fd411940987"} -->
