---
name: review
description: Run a focused code review using a stronger subagent model. By default reviews the current branch (all commits since it diverged from the default branch) for bugs, logic errors, security issues, and missed edge cases. Supports a custom revision range and a selectable reviewer model. Invoke via /skill:review, /skill:review main..HEAD, or /skill:review --model gpt-5.5.
---

# Code Review via Subagent

Launches the full `pi` interface (`pi --model <REVIEWER_MODEL>`) in a live tmux
pane to get a second opinion on code changes from a stronger model. The
reviewer writes its report to a file so the agent never has to scrape stdout.

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

| Alias              | Full ID                                |
| ------------------ | -------------------------------------- |
| `fable`, `fable-5` | `anthropic/claude-fable-5`             |
| `opus`, `opus-4.8` | `anthropic/claude-opus-4-8`            |
| `gpt`, `gpt-5.5`   | `openai-codex/gpt-5.5`                 |
| `gemini`           | `openrouter/google/gemini-3.5-flash`   |
| `glm`              | `openrouter/z-ai/glm-5.1`              |
| `kimi`             | `openrouter/moonshotai/kimi-k2.6`      |
| `deepseek`         | `openrouter/deepseek/deepseek-v4-pro`  |
| `minimax`          | `openrouter/minimax/minimax-m3`        |

## Instructions

1. **Parse the arguments.**
   - Extract the reviewer model from `--model`/`-m` if present, resolving
     aliases via the table above. Otherwise use `anthropic/claude-opus-4-8`.
   - Treat any remaining non-flag argument as the git revision `RANGE`.
   - **Generate a unique run ID** so parallel reviews never clash on shared
     `/tmp` paths. Use it as `REVIEW_ID` in every temp filename below:
     ```bash
     REVIEW_ID=$(uuidgen 2>/dev/null || od -An -N8 -tx1 /dev/urandom | tr -d ' \n')
     ```
     All the temp files in the steps that follow are named
     `/tmp/pi-review-<purpose>-$REVIEW_ID.*` — substitute the actual generated
     ID when you run the commands.

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

4. **Save the diff** to a temp file (unique per run):
   ```bash
   git diff <RANGE> > /tmp/pi-review-diff-$REVIEW_ID.md
   ```

5. **Run the reviewer subagent in a live tmux pane.** Write the prompt and a
   tiny runner script to temp files (this avoids nested-quoting problems when
   the prompt is long), then launch the full `pi` TUI in a detached split pane
   the user can watch in real time, and block until the reviewer signals it is
   done.

   First write the prompt (note the diff path includes the run ID). The prompt
   tells the reviewer to write its report to the output file and then create a
   done-file as its final action — this is how the agent knows it finished,
   instead of scraping stdout:
   ```bash
   cat > /tmp/pi-review-prompt-$REVIEW_ID.txt <<EOF
   You are a senior engineer reviewing a code diff. The diff is at /tmp/pi-review-diff-$REVIEW_ID.md. Read it, then review it focusing ONLY on bugs, logic errors, security issues, missed edge cases, and opportunities to simplify/DRY the code. You have full access to the repository in the current working directory — read related files, trace callers, and run git commands as needed to understand the change in context. Do NOT comment on style, naming, or minor preferences. For each finding, cite the file and line, explain the issue, and suggest a fix. Your report should be a numbered list, or say 'No issues found' if the code is clean.

   IMPORTANT — how to deliver your report: do NOT just print it to the screen. When your review is complete, WRITE the full report to the file /tmp/pi-review-output-$REVIEW_ID.md using your file-writing tool. Then, as your VERY LAST action, create an empty signal file by running: touch /tmp/pi-review-done-$REVIEW_ID. Only create the done-file after the report file has been fully written.
   EOF
   ```

   Then write the runner and launch it. The runner execs the full interactive
   `pi` TUI, passing the prompt as a **positional message** (NOT via `-p`,
   which is the alias for `--print` and would run non-interactively). This
   seeds the interactive session with the prompt so the user sees live
   progress (tool calls, thinking, edits) in the pane. Because it is
   the real interactive interface, the pane naturally stays open after the
   review finishes — the user can scroll the session, ask follow-ups, or close
   it themselves:
   ```bash
   # $1 = reviewer model, $2 = run ID. Every path is namespaced by the run ID.
   cat > /tmp/pi-review-run-$REVIEW_ID.sh <<'EOF'
   #!/usr/bin/env bash
   MODEL="$1"; ID="$2"
   # Pass the prompt as a POSITIONAL message, not via -p/--print: -p is the
   # alias for --print (non-interactive, process-and-exit). A positional
   # message launches the full interactive TUI seeded with that first message.
   exec pi --model "$MODEL" "$(cat /tmp/pi-review-prompt-$ID.txt)"
   EOF
   chmod +x /tmp/pi-review-run-$REVIEW_ID.sh
   rm -f /tmp/pi-review-output-$REVIEW_ID.md /tmp/pi-review-done-$REVIEW_ID

   if [ -n "$TMUX" ]; then
     # Running inside tmux: spawn a detached split pane (-d keeps the agent's
     # pane focused) so the user watches the live pi TUI without losing focus
     # on the conversation with this agent.
     #
     # Pick the split direction from the current pane's aspect ratio so each
     # pane stays as close to square as possible. Terminal cells are roughly
     # twice as tall as they are wide, so multiply the height (in cells) by 2
     # to compare visual extents. If the pane is visually wider than tall,
     # split side-by-side (-h); otherwise stack them top/bottom (-v).
     PANE_W=$(tmux display-message -p '#{pane_width}')
     PANE_H=$(tmux display-message -p '#{pane_height}')
     if [ "$PANE_W" -gt "$((PANE_H * 2))" ]; then SPLIT_DIR=-h; else SPLIT_DIR=-v; fi
     tmux split-window "$SPLIT_DIR" -d "/tmp/pi-review-run-$REVIEW_ID.sh '<REVIEWER_MODEL>' '$REVIEW_ID'"
     # Block until the subagent signals completion via the run-specific done-file.
     while [ ! -f /tmp/pi-review-done-$REVIEW_ID ]; do sleep 2; done
     echo "Reviewer finished; report written to /tmp/pi-review-output-$REVIEW_ID.md"
   else
     # Not in tmux: fall back to a normal blocking run.
     /tmp/pi-review-run-$REVIEW_ID.sh '<REVIEWER_MODEL>' "$REVIEW_ID"
   fi
   ```
   The pane shows the live pi interface and stays open afterward. The agent
   unblocks as soon as the done-file appears and reads the full review from
   `/tmp/pi-review-output-$REVIEW_ID.md`.

6. **Present the findings** (read them from `/tmp/pi-review-output-$REVIEW_ID.md`) to the user, then ask whether they'd like you to
   address any of them.

## Notes

- The default reviewer model is `anthropic/claude-opus-4-8`, used for deep code
  analysis. Override it per-invocation with `--model`.
- The subagent runs the **full interactive `pi` TUI** (not `--print`), so the
  user sees its live progress — thinking, tool calls, file reads — stream in
  the pane. The reviewer is instructed to write its report to
  `/tmp/pi-review-output-$REVIEW_ID.md` and then `touch` a done-file as its
  final action; the agent never scrapes stdout.
- All temp files are namespaced with a per-invocation random `REVIEW_ID`
  (`/tmp/pi-review-*-$REVIEW_ID.*`), so multiple reviews can run in parallel
  without clobbering each other's diff, prompt, output, or done-file.
- When invoked inside tmux, the reviewer runs in a detached split pane so the
  user can watch the live pi TUI without losing focus on the conversation with
  this agent. The split direction adapts to the current pane's aspect ratio
  (accounting for cells being ~twice as tall as wide): side-by-side (`-h`) when
  the pane is wider than tall, stacked (`-v`) otherwise, keeping both panes
  close to square. The agent blocks (polling `/tmp/pi-review-done-$REVIEW_ID`)
  until the reviewer writes its done-file, then reads the report from
  `/tmp/pi-review-output-$REVIEW_ID.md`. Because it is the real interactive
  interface, the pane stays open after the review for the user to scroll, ask
  follow-ups, or close themselves. Outside tmux it falls back to a normal
  blocking run.
- The subagent runs in the current working directory and has full tool access,
  so it can read any file, trace callers, and run git commands to understand
  the change in its broader context — it is not limited to the diff alone.
- Findings about pre-existing code outside the diff should be noted but
  flagged as out-of-scope.
