---
name: coff-review-diff-code
description: Review the current branch's diff from six fixed lenses, spawning one subagent per lens, and report the aggregated findings. No fixes.
license: MIT
---

## Procedure

1. Determine the review target. The base branch is the default branch `origin/HEAD` points to, or whichever of master / main exists locally. The target is the diff between the base and the working tree, plus untracked files. If the diff is empty, report so and stop.

   ```bash
   base=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)   # 例: origin/master
   if [ -z "$base" ]; then
     for b in master main; do git show-ref --verify -q "refs/heads/$b" && { base=$b; break; }; done
   fi
   git diff --stat "$base" && git status --short --untracked-files=all
   ```

2. Launch one subagent per lens, in parallel. Run the subagents read-only; do not let them modify files. Pass each subagent only the base branch name and its assigned lens, and have the subagent fetch the diff itself (take the diff against the working tree with `git diff <base>`, and directly read the untracked files listed by `git status --short --untracked-files=all`; do not embed a large diff in the prompt). Do not let it report findings outside its lens.

   Lenses:

   1. General review (correctness, consistency with existing conventions, regressions)
   2. YAGNI (unused extension points, re-checks already guaranteed upstream, safeguards against situations that cannot happen)
   3. Is the spec needlessly complex?
   4. Is the issue overly complex (is the issue included in the diff commensurate with the substance of the change)?
   5. Missed sweep of same-kind anti-patterns (does a problem of the same kind as what the diff fixed remain outside the diff? Searching outside the diff is limited to that same-kind pattern)
   6. Existence and thinness of the entry artifact (was the requested entry built, and is it not bloated with a copy of the spec?)

   Lenses 4 and 6 take their judgment material from issue files in the diff; with none, return "not applicable".

3. Aggregate the findings and report. Merge findings on the same location or with the same gist, put correctness-related findings first, and list each with its lens and location (path:line). Do not fix anything; adoption is the caller's call.

## Notes

- If the codex-delegate skill is installed, you can delegate to it to run in a separate process.
<!--{"src":".coff/src/coff-review-diff-code.skill.md","md5":"ca5daca1df02585c57d7af992ddae95e"} -->
