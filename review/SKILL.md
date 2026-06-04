---
name: review
description: Run a focused code review using a stronger subagent model. By default reviews the current branch (all commits since it diverged from the default branch) for bugs, logic errors, security issues, and missed edge cases. Supports a custom revision range and a selectable reviewer model. Invoke via /skill:review, /skill:review main..HEAD, or /skill:review --model gpt-5.5.
---

# Code Review via Subagent

Runs `pi --model <REVIEWER_MODEL> --print` to get a second opinion on code
changes from a stronger model.

## Usage

```
/skill:review                          # Review the current branch vs the default branch
/skill:review HEAD~3..HEAD             # Review a specific revision range
/skill:review main..HEAD               # Review all changes vs main
/skill:review --model gpt-5.5          # Review the current branch with a specific model
/skill:review main..HEAD --model gpt-5.5   # Both
```

Arguments (any order, all optional):

- **`--model <name>` / `-m <name>`** — the reviewer model. Accepts a short
  alias or a full `provider/model` ID. Defaults to `anthropic/claude-opus-4-8`.
- **Any other argument** — a git revision range. If omitted, defaults to the
  current branch (see below).

### Model aliases

Map common short names to full IDs; pass anything containing a `/` through
unchanged:

| Alias              | Full ID                      |
| ------------------ | ---------------------------- |
| `opus`, `opus-4.8` | `anthropic/claude-opus-4-8`  |
| `gpt`, `gpt-5.5`   | `openai/gpt-5.5`             |

## Instructions

1. **Parse the arguments.**
   - Extract the reviewer model from `--model`/`-m` if present, resolving
     aliases via the table above. Otherwise use `anthropic/claude-opus-4-8`.
   - Treat any remaining non-flag argument as the git revision `RANGE`.

2. **Determine the range** when none was provided (the default — review the
   current branch):
   ```bash
   # Find the default branch (the one the repo diverges from)
   BASE=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null \
     || echo origin/main)
   # Fall back through common names if origin/HEAD isn't set
   git rev-parse --verify "$BASE" >/dev/null 2>&1 || BASE=origin/main
   git rev-parse --verify "$BASE" >/dev/null 2>&1 || BASE=main
   git rev-parse --verify "$BASE" >/dev/null 2>&1 || BASE=master
   RANGE="$BASE...HEAD"
   ```
   The three-dot `$BASE...HEAD` diffs from the merge-base, i.e. exactly the
   changes introduced on the current branch. If the current branch *is* the
   default branch (empty diff), inform the user and offer to review
   `HEAD~1..HEAD` instead.

3. **Generate the diff.** Run:
   ```bash
   git diff <RANGE>
   ```
   If the diff is empty, try `git diff <RANGE> --stat` to confirm the range is
   valid, and inform the user.

4. **Save the diff** to a temp file:
   ```bash
   git diff <RANGE> > /tmp/pi-review-diff.md
   ```

5. **Run the reviewer subagent.** Execute (substituting the resolved model):
   ```bash
   pi --model <REVIEWER_MODEL> --print -p "You are a senior engineer reviewing a code diff. The diff is at /tmp/pi-review-diff.md. Read it, then review it focusing ONLY on bugs, logic errors, security issues, and missed edge cases. You have full access to the repository in the current working directory — read related files, trace callers, and run git commands as needed to understand the change in context. Do NOT comment on style, naming, or minor preferences. For each finding, cite the file and line, explain the issue, and suggest a fix. Output a numbered list, or say 'No issues found' if the code is clean."
   ```

6. **Present the findings** to the user, then ask whether they'd like you to
   address any of them.

## Notes

- The default reviewer model is `anthropic/claude-opus-4-8`, used for deep code
  analysis. Override it per-invocation with `--model`.
- The subagent runs in `--print` (non-interactive) mode — it reads the diff
  file, explores the repo as needed, and exits with its review.
- The subagent runs in the current working directory and has full tool access,
  so it can read any file, trace callers, and run git commands to understand
  the change in its broader context — it is not limited to the diff alone.
- Findings about pre-existing code outside the diff should be noted but
  flagged as out-of-scope.
