---
name: compile
description: Build entry point for the coff repo. A wrapper around `/coff-compile` that also syncs the distribution mirror `skills/` for skills declaring `coff-dist`. Arguments pass through as-is.
---

## Procedure

1. Run `/coff-compile` (`.claude/skills/coff-compile/SKILL.md`) with the received arguments as-is.
2. Mirror sync. Skip this step when the arguments include `--lint-only`. For each skill-type source whose frontmatter has `coff-dist: true`, sync the distribution mirror `skills/<name>/` as a directory-level copy of the canonical `.claude/skills/<name>/`.

   ```bash
   mkdir -p skills
   for src in .coff/src/*.skill.md; do
     sed -n '2,/^---$/p' "$src" | grep -q '^coff-dist:[[:space:]]*true' || continue
     name=$(basename "$src" .skill.md)
     src_dir=".claude/skills/$name"
     dst_dir="skills/$name"
     diff -r "$src_dir" "$dst_dir" >/dev/null 2>&1 && continue
     tmp_dir=$(mktemp -d "skills/.${name}.XXXXXX")
     cp -R "$src_dir/." "$tmp_dir/" || { rm -rf "$tmp_dir"; echo "mirror failed: $name"; exit 1; }
     rm -rf "$dst_dir"
     mv "$tmp_dir" "$dst_dir"
     echo "mirrored: $name"
   done
   ```

3. Add the sync output (`mirrored: <name>`), if any, to coff-compile's report.

## Rules

- `coff-dist` is the coff repo's distribution declaration, and this wrapper is its only interpreter.
- Removing the mirror of a source that dropped the declaration is done by hand.
<!--{"src":".coff/src/compile.skill.md","md5":"754ee9f5b52592aed0c85a06160495ea"} -->
