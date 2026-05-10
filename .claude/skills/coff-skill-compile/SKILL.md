---
name: coff-skill-compile
description: Build coff skill sources (`.coff/src/`) into runtime skills under `.claude/skills/`. No args = all; `<name>` for individual; `--lint-only` for pre-check only; `--force` to rebuild even unchanged sources. Run only when explicitly invoked.
---

## Inputs / Outputs

- Input glob: `.coff/src/*.skill.md`
- Source `.coff/src/<name>.skill.md` → output `.claude/skills/<name>/SKILL.md`
- `<name>` is the source filename with `.skill.md` stripped.

## Options

Args (any order, combinable):

- `--lint-only`: stop after the lint phase. Skip both the compile and the permission gate.
- `--force`: ignore md5-match skip; process all targets.
- `<path|name> [<path|name> ...]`: process only the specified sources. Accepts full path `.coff/src/foo.skill.md`, bare name `foo`, or filename `foo.skill.md`. No args = all `.coff/src/*.skill.md`.

Examples:
- `/coff-skill-compile --lint-only` — lint only (md5-matched files skipped).
- `/coff-skill-compile --force` — rebuild all, ignoring md5.
- `/coff-skill-compile foo` — lint+compile only `foo`.

## 1. Identify build targets

```bash
src=.coff/src/<name>.skill.md
dst=.claude/skills/<name>/SKILL.md
src_md5=$(md5sum "$src" | cut -d' ' -f1)
dst_md5=$(tail -n 1 "$dst" 2>/dev/null | grep -oP '"md5":"\K[a-f0-9]{32}')
[ "$src_md5" = "$dst_md5" ] && echo skip || echo build
```

Empty source is a hard error — report and continue.

## 2. Lint

For each build target, detect the following:

| Candidate | Type | Action | Default |
|---|---|---|---|
| WHY / design rationale / big-picture explanation | safe | wrap in `<!-- -->` | approve ON |
| Human-targeted meta instruction (e.g. "do not hand-edit") | safe | wrap in `<!-- -->` | approve ON |
| Tautology / stylized restatement (especially "positive form X. negative form X." patterns) | safe | wrap the latter in `<!-- -->` | approve ON |
| Redundant inverse / Yes-No enumeration (condition + "Yes→A / No→B" listing, or "X then Y. not X then not Y." pattern) | safe | wrap the enumeration in `<!-- -->` | approve ON |
| WHAT duplication (frontmatter `description` ⇄ opening paragraph, etc.) | lossy | delete/merge | approve OFF |
| H1 heading ⇄ frontmatter `name` duplication | lossy | delete | approve OFF |
| Frontmatter `description` is verbose | lossy | shorten | approve OFF |
| Structural duplication (high-level summary section ⇄ detailed sections both describing the same procedure) | lossy | delete the summary | approve OFF |
| Redundant examples (a generalization rule followed by an exhaustive enumeration of combinations — e.g. listing every combination after stating `combinable`) | lossy | trim to 2-3 representative examples | approve OFF |

Heuristic: if the sentence is removed from the **compiled output**, can the executing LLM still complete the procedure?

Excluded from scope:
- Anything already inside `<!-- -->`.
- Inside frontmatter, fenced code blocks, or inline code spans.

Exception: frontmatter `description` is checked separately. If it contains anything beyond WHAT and user-facing HOW (args, invocation) — internal procedure, implementation details, or WHY — flag as lossy and propose a shortened version, quoting the parts to drop.

## 3. Interactive approval

Skip this step if 0 candidates.

Otherwise, present candidates in a batch via `AskUserQuestion` with `multiSelect=true`:

- Group by file. Each option label includes target line, quoted text, type (`safe` / `lossy`), recommendation, and post-apply preview.
- Mark recommendation with a leading tag in the label. Examples: `[safe・推奨]`, `[lossy]`.
- Only items the user selects are written back to the source.

Write-back:
- safe (wrap in comment): wrap the range in `<!-- ... -->`. Do not alter wording.
- lossy: replace with the proposed rewrite, or delete the line.

If candidates don't fit in a single batch, split per-file → per-section and present sequentially.

## 4. Compile permission gate

If lint surfaced ≥1 candidate (regardless of whether any were applied), confirm explicitly before compiling:

> "Lint 完了。N 件適用、M 件却下。コンパイルしますか？"

If rejected, abort. If approved, proceed to 5.

## 5. Compile

For files modified by lint, the `src_md5` from §1 is stale; recompute before writing the footer. For each build target:

a. **Translate Japanese → English.** Rewrite prose, headings, list items, and the frontmatter `description` value into concise English.

   DO NOT translate (preserve byte-for-byte):
   - Quoted string literals the model must match against or emit verbatim. Example: in `ファイル名が "注文" から始まるファイル`, `"注文"` stays in Japanese; only the surrounding sentence is translated → `files whose name starts with "注文"`.
   - Code identifiers, function names, file paths, CLI flags, regex patterns, command arguments.
   - Contents of fenced code blocks (` ``` … ``` `) and inline code spans.
   - Frontmatter keys. The frontmatter `name` value. Other frontmatter values that act as identifiers.
   - Proper nouns: product names, project names, people's names.
   - UI strings, error messages, and any other strings the user/model must reproduce verbatim.

   When in doubt, leave the original.

b. **Strip HTML/markdown comments from the body.** Remove every `<!-- ... -->` block in the body. Do not strip comments inside fenced code blocks or inline code spans. Do not touch the frontmatter block.

c. **Preserve frontmatter structure.** The leading `---` … `---` block must remain valid YAML frontmatter in the output. If the source has no frontmatter, abort with an error.

d. **Write the output and append the footer.** Footer goes on the last line, after the body, outside any code block.

   ```bash
   mkdir -p "$(dirname "$dst")"
   printf '%s\n<!--{"src":"%s","md5":"%s"} -->\n' "$body" "$src" "$src_md5" > "$dst"
   ```

## 6. Report

Report each source as one of:
- `compiled` (with `(N applied)` if lint applied any)
- `linted (N applied, M rejected)` — under `--lint-only`, or when the permission gate was rejected
- `failed: <reason>`

Do not list skipped files. Do not list anything when `--lint-only` finds 0 candidates.

## Rules

- Destructive source changes only via approved lint items.
- Do not touch the frontmatter `name` value or any identifier that forms an output path, even during lint.
- Both lint and compile are atomic: no partial writes on mid-step failure.

<!--{"src":".coff/src/coff-skill-compile.skill.md","md5":"1a8a36546ef876b38ecb3b4d07372b86"} -->
