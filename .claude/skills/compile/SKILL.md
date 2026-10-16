---
name: compile
description: Build entry point for the coff repo. A wrapper around `/coff-compile` that also syncs the distribution mirror `skills/` for skills declaring `coff-dist`. Arguments pass through as-is.
---

## Procedure

1. Run `/coff-compile` (`.claude/skills/coff-compile/SKILL.md`) with the received arguments as-is.
2. Mirror sync. Skip this step when the arguments include `--lint-only`. For each skill-type source whose frontmatter has `coff-dist: true` (both the single-file `.coff/src/<name>.skill.md` and the directory `.coff/src/<name>.skill/SKILL.md`), sync the distribution mirror `skills/<name>/` as a whole-directory copy of the canonical `.claude/skills/<name>/`. Recopy and report only when they differ. If the canonical directory is missing, leave the mirror alone.

   ```bash
   for src in .coff/src/*.skill.md .coff/src/*.skill/SKILL.md; do
     [ -e "$src" ] || continue
     sed -n '2,/^---$/p' "$src" | grep -q '^coff-dist:[[:space:]]*true' || continue
     case "$src" in
       *.skill/SKILL.md) name=$(basename "$(dirname "$src")" .skill) ;;
       *)                name=$(basename "$src" .skill.md) ;;
     esac
     [ -d ".claude/skills/$name" ] || continue
     diff -r ".claude/skills/$name" "skills/$name" >/dev/null 2>&1 && continue
     mkdir -p skills && rm -rf "skills/$name" && cp -R ".claude/skills/$name" "skills/$name" && echo "mirrored: $name"
   done
   ```

3. Add the sync output (`mirrored: <name>`), if any, to coff-compile's report.

## Rules

- `coff-dist` is the coff repo's distribution declaration, and this wrapper is its only interpreter.
- Removing the mirror of a source that dropped the declaration is done by hand.
<!--{"src":".coff/src/compile.skill.md","md5":"148759c2a6a64ec96a131c06d7e96bb4"} -->
