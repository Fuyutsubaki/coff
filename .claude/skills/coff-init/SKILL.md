---
name: coff-init
description: Set up the coff skill suite in a target repo. Bulk-installs the missing coff skills and initializes the issue workflow (create `issue/`, add the conventions section to the agent's rules file).
license: MIT
---

## Procedure

1. Prerequisites: confirm the current directory is a git repository, the `gh` CLI is available, and `gh skill --help` succeeds (an agent-skills-capable version). If anything is missing, report what's lacking and stop.
2. Detect the agent: judge by the tail of this SKILL.md's location (the agent presents it when loading the skill). `.claude/skills/coff-init` means claude-code; `.agents/skills/coff-init` means codex. If no path was presented, judge by whether `.claude/skills/coff-init` and `.agents/skills/coff-init` exist under the cwd; if both exist, ask the user. Below, `<agent>` is the detected value, `<dir>` is its skills directory (`.claude/skills/` or `.agents/skills/`), and `<rules>` is the agent's rules file (CLAUDE.md for claude-code, AGENTS.md for codex).
3. Install sibling skills: for each coff skill whose directory does not exist under `<dir>`, install it one at a time with the command below. Judge "missing" by directory existence only; do not compare versions.

   ```bash
   # 対象: coff-detail-issue coff-issue-create coff-issue-polish coff-issue-done
   #       coff-issue-list coff-compile coff-japanese-tech-writing
   #       coff-argument-gap-edit coff-review-diff-code
   gh skill install Fuyutsubaki/coff <name> --agent <agent>
   ```

   Do not omit `--agent <agent>`. This needs network access and write access to `<dir>` (the codex sandbox makes `.agents/` read-only), so if it fails inside a sandbox, rerun with approval.
4. Initialize:
   - Create the `issue/` directory if absent.
   - Add the coff conventions section to `<rules>`. Create the file if absent. If the heading `## coff` already exists, do nothing. Leave existing content untouched and append the following section at the end, replacing `<dir>` with the detected skills directory and `<build>` with nothing for claude-code, or with 「（`--out .agents` で実体を出力する）」 for codex.

     ```markdown
     ## coff
     - `<dir>` 配下の coff 成果物（skills など）は手で編集しない。変更は `.coff/src/` のソースを編集し、coff-compile skill でビルドする<build>。
     - issue 運用の入口は coff-issue-create skill。流れは create → polish → 実装 → done。一覧は coff-issue-list skill。
     ```
5. Report: report the detected agent, the installed skills, and the initialization results. Also briefly introduce the issue workflow (create → polish → implement → done), and note that the `.coff/src/` conventions with the coff-compile skill are available for source-managing one's own skills.

## Exit bar

- The coff skill suite is present under `<dir>`, and `issue/` and the coff section of `<rules>` exist.
<!--{"src":".coff/src/coff-init.skill.md","md5":"5fa8afe8f76bc488329fb605446470bb"} -->
