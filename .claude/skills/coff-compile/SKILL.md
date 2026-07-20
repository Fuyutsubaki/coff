---
name: coff-compile
description: Build coff sources (`.coff/src/`) into runtime artifacts under `.claude/`. `.skill.md` → skills, `.outputstyle.md` → output-styles, `.agent.md` → agents. No args = all; `<name>` for individual; `--lint-only` for pre-check only; `--force` to rebuild even unchanged sources. `--out` overrides the output destination, `--ref` writes reference stubs, and `--agent` follows per-agent defaults such as codex.
license: MIT
---

## Inputs / Outputs

Each source type determines its output path. `<name>` is the source filename with the `.<type>.md` suffix stripped.

| Source glob | Output path |
|---|---|
| `.coff/src/*.skill.md` | `.claude/skills/<name>/SKILL.md` |
| `.coff/src/*.outputstyle.md` | `.claude/output-styles/<name>.md` |
| `.coff/src/*.agent.md` | `.claude/agents/<name>.md` |

The input glob set is all globs above. With no args, all of them are targeted.

## Options

Args (any order, combinable):

- `--lint-only`: run lint only and stop. The pre-compile confirmation is also skipped.
- `--force`: ignore md5-match skip and process all targets.
- `--out <root>`: replace the default output root `.claude`. The per-type sublayout (`skills/<name>/SKILL.md` etc.) stays the same under the new root.
- `--ref`: use together with `--out`; write a reference stub pointing at the canonical file instead of a copy of the compiled body. `--ref` without `--out` is an error; abort.
- `--agent <name>`: preset that derives `--out` and `--ref` from the agent name (table below). Repeatable. Default is `claude-code`. Explicit `--out` / `--ref` take precedence over the preset.
- `<path|name> [<path|name> ...]`: process only the specified sources. Accepts full path `.coff/src/foo.skill.md` or `.coff/src/foo.outputstyle.md`, bare name `foo`, or filename `foo.skill.md`. No args = all globs. If a bare name `foo` matches more than one source type (e.g. both `foo.skill.md` and `foo.outputstyle.md` exist), report it as ambiguous and require a full path or filename.

Examples:
- `/coff-compile --lint-only` — lint only (md5-matched files skipped).
- `/coff-compile --force` — rebuild all, ignoring md5.
- `/coff-compile foo` — lint+compile only `foo`.
- `/coff-compile my-style` — build only the my-style output style.
- `/coff-compile --agent codex` — write codex reference stubs under `.agents/skills/`.

## Agent presets and reference output

The real body (the canonical copy) lives in exactly one place in the repository; other agents get a reference stub.

| agent | Output root | Placement mode | Source types |
|---|---|---|---|
| `claude-code` (default) | `.claude/` | body | skill / outputstyle / agent |
| `codex` | `.agents/` | reference | skill only |

- Claude-code-specific types (outputstyle / agent) are out of scope when building for other agents; leave them out of the report as well.
- A reference stub carries the same frontmatter as the canonical output (after `coff-*` key removal); its body is a single line with the relative path to the canonical file. It gets a footer under the same rule, used for skip detection.

  ```markdown
  ---
  name: <name>
  description: <正本と同一>
  ---

  This file is a reference. Read and follow `../../../.claude/skills/<name>/SKILL.md`.
  <!--{"src":".coff/src/<name>.skill.md","md5":"<src md5>"} -->
  ```

- Build order is canonical → references. When writing a reference, if the canonical file does not exist, report it as an error.

## 1. Identify build targets

Determine the type from the source extension and derive the output path set `dsts`.

```bash
case "$src" in
  *.skill.md)       name=$(basename "$src" .skill.md);       dsts=".claude/skills/$name/SKILL.md" ;;
  *.outputstyle.md) name=$(basename "$src" .outputstyle.md); dsts=".claude/output-styles/$name.md" ;;
  *.agent.md)       name=$(basename "$src" .agent.md);       dsts=".claude/agents/$name.md" ;;
  *) echo "unknown source type: $src"; continue ;;
esac
src_md5=$(md5sum "$src" | cut -d' ' -f1)
verdict=skip
for dst in $dsts; do
  dst_md5=$(tail -n 1 "$dst" 2>/dev/null | grep -oP '"md5":"\K[a-f0-9]{32}')
  [ "$src_md5" = "$dst_md5" ] || verdict=build
done
echo $verdict
```

Skip only when every output's md5 matches.

With `--out` / `--agent`, apply the root replacement and reference additions to this derivation. Reference outputs also join `dsts`; skip detection applies the same footer rule to every output.

Empty sources are reported as errors; continue to the next file.

## 2. Lint

For each selected source, detect the following patterns.

| Candidate | Action | Recommended |
|---|---|---|
| Design rationale or big-picture explanation (WHY) | wrap in `<!-- -->` | ON |
| Reader-facing notes (e.g. "do not hand-edit") | wrap in `<!-- -->` | ON |
| Sentences that say the same thing with different wording (especially "positive X. negative X." pairs) | delete the latter | ON |
| Redundant restatement of a condition, or Yes/No enumeration ("Yes→A / No→B" list, or "X then Y. not X then not Y." pattern) | delete the redundant side | ON |
| Same content duplicated (frontmatter `description` ⇄ opening paragraph, etc.) | delete or merge | OFF |
| H1 heading ⇄ frontmatter `name` duplication | delete | OFF |
| Frontmatter `description` is verbose | shorten | OFF |
| Structural duplication (a high-level summary section and detailed sections both describe the same procedure) | delete the summary | OFF |
| Redundant examples (a generalization rule followed by an exhaustive enumeration of combinations — e.g. listing every combination after stating `combinable`) | trim to 2-3 representative examples | OFF |

Heuristic: if the sentence is removed from the **compiled output**, can the executing LLM still complete the procedure? If yes, flag it as a candidate.

Excluded from scope:
- Anything already inside `<!-- -->`.
- Inside frontmatter, fenced code blocks, or inline code spans.

Exception: frontmatter `description` is checked separately. For a skill source, if it contains anything beyond WHAT and user-facing HOW (args, invocation) — internal procedure, implementation details, or WHY — flag as a shortening candidate (recommended OFF), quoting the parts to drop and proposing a shortened version. For an agent source, the `description` is what the model uses to decide whether to spawn the subagent, so treat it like a skill (anything beyond WHAT and when-to-spawn — internal procedure, implementation details, or WHY — is a shortening candidate, recommended OFF). An output-style source has no concept of args/invocation, so flag anything beyond WHAT (what the style is for) as a shortening candidate (recommended OFF).

## 3. Interactive approval

If candidates exist, present them in a batch via `AskUserQuestion` with `multiSelect=true`.

- Group candidates by file. Each option label includes the target line, quoted text, action, recommendation, and post-apply preview.
- Mark the recommendation with a leading tag in the label. Use `[推奨]` for recommended candidates and `[要判断]` for those needing user judgment.
- Only items the user selects are written back to the source.

Write-back:
- Comment-out candidates: wrap the range in `<!-- ... -->`. Do not alter the wording.
- Delete/rewrite candidates: replace with the proposed rewrite, or delete the line.

If candidates don't fit in a single batch, split per-file → per-section and present sequentially.

## 4. Pre-compile confirmation

If lint surfaced ≥1 candidate (regardless of whether any were applied), confirm explicitly before compiling:

> "Lint 完了。N 件適用、M 件却下。コンパイルしますか？"

If rejected, abort. If approved, proceed to 5.

## 5. Compile

If lint modified the source, recompute the md5 before writing the footer. For each build target:

a. **Translate Japanese to English.** Rewrite prose, headings, list items, and the frontmatter `description` value into concise English. If the source frontmatter has `coff-translate: false`, skip this step entirely (output the body and `description` untranslated).

   But do not translate (preserve byte-for-byte):
   - Quoted string literals the model uses for matching or verbatim emission. Example: in `ファイル名が "注文" から始まるファイル`, `"注文"` stays in Japanese; only the surrounding sentence is translated → `files whose name starts with "注文"`.
   - Code identifiers, function names, file paths, CLI flags, regex patterns, command arguments.
   - Contents of fenced code blocks (` ``` … ``` `) and inline code spans.
   - Frontmatter keys, the `name` value, and other frontmatter values that act as identifiers.
   - Proper nouns (product names, project names, people's names).
   - UI strings, error messages, and any other strings the user/model must reproduce verbatim.

   When in doubt, leave the original.

b. **Strip HTML/markdown comments from the body.** Remove every `<!-- ... -->` block in the body. Do not strip comments inside fenced code blocks or inline code spans. Do not touch the frontmatter block.

c. **Preserve frontmatter structure.** The leading `---` … `---` block must remain valid YAML frontmatter in the output. If the source has no frontmatter, abort with an error. Remove every key starting with `coff-` from the output frontmatter.

d. **Write the output and append the footer.** Footer goes on the last line, after the body, outside any code block. Output-style files also get the footer; it is a plain markdown file, so the trailing HTML comment is harmless and is also used for skip detection. For reference-mode outputs, write the stub from "Agent presets and reference output" instead of the body.

   ```bash
   for dst in $dsts; do
     mkdir -p "$(dirname "$dst")"
     printf '%s\n<!--{"src":"%s","md5":"%s"} -->\n' "$body" "$src" "$src_md5" > "$dst"
   done
   ```

## 6. Report

Report each source as one of:
- `compiled` (with the applied lint count if any)
- `linted (N applied, M rejected)` — under `--lint-only`, or when the pre-compile confirmation was rejected
- `failed: <reason>`

Do not list skipped files. Do not list anything when `--lint-only` finds 0 candidates.

## Rules

- The source is only modified via lint approvals.
- Do not touch the frontmatter `name` value or any identifier that forms an output path, even during lint.
- Both lint and compile are atomic: no partial writes if a step fails mid-way.
<!--{"src":".coff/src/coff-compile.skill.md","md5":"9b709abed7fa8af9366d74dcd9684cf3"} -->
