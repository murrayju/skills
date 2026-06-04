---
name: review
description: Run a focused code review using an Opus subagent. Reviews the diff of the latest commit (or a specified range) for bugs, logic errors, security issues, and missed edge cases. Invoke via /skill:review or /skill:review HEAD~3..HEAD.
---

# Code Review via Opus Subagent

Runs `pi --model anthropic/claude-opus-4-8 --print` to get a second opinion on code changes from a stronger model.

## Usage

```
/skill:review                    # Review the latest commit (HEAD~1..HEAD)
/skill:review HEAD~3..HEAD       # Review a specific range
/skill:review main..HEAD         # Review all changes vs main
```

Any argument after the command is treated as the git revision range. If no
argument is given, defaults to `HEAD~1..HEAD` (the most recent commit).

## Instructions

1. **Determine the range.** If the user provided an argument, use it as the
   git revision range. Otherwise use `HEAD~1..HEAD`.

2. **Generate the diff.** Run:
   ```bash
   git diff <RANGE>
   ```
   If the diff is empty, try `git diff <RANGE> --stat` to confirm the range is
   valid, and inform the user.

3. **Save the diff** to a temp file:
   ```bash
   git diff <RANGE> > /tmp/pi-review-diff.md
   ```

4. **Run the Opus subagent.** Execute:
   ```bash
   pi --model anthropic/claude-opus-4-8 --print -p "You are a senior engineer reviewing a code diff. The diff is at /tmp/pi-review-diff.md. Read it, then review it focusing ONLY on bugs, logic errors, security issues, and missed edge cases. You have full access to the repository in the current working directory — read related files, trace callers, and run git commands as needed to understand the change in context. Do NOT comment on style, naming, or minor preferences. For each finding, cite the file and line, explain the issue, and suggest a fix. Output a numbered list, or say 'No issues found' if the code is clean."
   ```

5. **Present the findings** to the user, then ask whether they'd like you to
   address any of them.

## Notes

- The review model is `anthropic/claude-opus-4-8`, used for deep code analysis.
- The subagent runs in `--print` (non-interactive) mode — it reads the diff
   file, explores the repo as needed, and exits with its review.
- The subagent runs in the current working directory and has full tool access,
   so it can read any file, trace callers, and run git commands to understand
   the change in its broader context — it is not limited to the diff alone.
- Findings about pre-existing code outside the diff should be noted but
  flagged as out-of-scope.
