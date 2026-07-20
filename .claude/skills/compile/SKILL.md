---
name: compile
description: Build entry point for the coff repo. Forwards its arguments to `/coff-compile`, then syncs the distribution mirror `skills/<name>/SKILL.md` for skills declaring `coff-dist`.
---

## Procedure

1. Run `/coff-compile` (`.claude/skills/coff-compile/SKILL.md`) with the received arguments as-is.
2. Mirror sync. Skip this step when the arguments include `--lint-only`. For each skill-type source whose frontmatter has `coff-dist: true`, sync the distribution mirror `skills/<name>/SKILL.md` as a copy of the canonical `.claude/skills/<name>/SKILL.md`.

   ```bash
   for src in .coff/src/*.skill.md; do
     sed -n '2,/^---$/p' "$src" | grep -q '^coff-dist:[[:space:]]*true' || continue
     name=$(basename "$src" .skill.md)
     mkdir -p "skills/$name"
     cmp -s ".claude/skills/$name/SKILL.md" "skills/$name/SKILL.md" || cp ".claude/skills/$name/SKILL.md" "skills/$name/SKILL.md"
   done
   ```

3. Add one line `mirrored: <name> ...` to coff-compile's report when the sync rewrote any mirror.

## Rules

- `coff-dist` is the coff repo's distribution declaration, and this wrapper is its only interpreter (coff-compile does nothing with it beyond stripping `coff-` keys).
- Removing the mirror of a source that dropped the declaration is done by hand.
<!--{"src":".coff/src/compile.skill.md","md5":"a1adf35d079c3b1f75cbc1d87db63505"} -->
