---
name: review
description: Run a focused code review using a stronger subagent model. By default reviews the current branch (all commits since it diverged from the default branch) for bugs, logic errors, security issues, and missed edge cases. Supports a custom revision range and a selectable reviewer model. Invoke via /skill:review, /skill:review main..HEAD, or /skill:review --model gpt-5.5.
---

# Code Review via Subagent

Launches the full `pi` interface (`pi --model <REVIEWER_MODEL>`) in a live
multiplexer pane (herdr or tmux) to get a second opinion on code changes from a
stronger model. The reviewer writes its report to a file so the agent never has
to scrape stdout.

### Multiplexer detection

Step 5 picks a launch mode from the environment, in this order:

| Check                    | Mode                                                     |
| ------------------------ | -------------------------------------------------------- |
| `"$HERDR_ENV" = 1`       | herdr: split the agent's herdr pane (`$HERDR_PANE_ID`)   |
| `-n "$TMUX"`             | tmux: split the agent's tmux pane (`$TMUX_PANE`)         |
| neither                  | no pane: non-interactive `pi -p` in the agent's own shell |

herdr wins when both are set, because herdr injects `HERDR_ENV` and
`HERDR_PANE_ID` into the exact pane the agent runs in. For more herdr detail
(IDs, JSON output, safety rules), see the separate `herdr` skill. This skill
only needs the commands in step 5.

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
  alias or a full `provider/model` ID. Defaults to
  `openrouter/anthropic/claude-opus-5.5` (the `opus` alias).
- **Any other argument** — a git revision range. If omitted, defaults to the
  current branch (see below).

### Model aliases

Map common short names to full IDs; pass anything containing a `/` through
unchanged:

| Alias                           | Full ID                                 |
| ------------------------------- | --------------------------------------- |
| `fable`, `fable-5`              | `openrouter/anthropic/claude-fable-5.1` |
| `opus`, `opus-5`                | `openrouter/anthropic/claude-opus-5.5`  |
| `gpt`, `sol`                    | `openrouter/openai/gpt-6-sol`           |
| `astra`                         | `openrouter/openai/gpt-6-astra`         |
| `gemini`                        | `openrouter/google/gemini-3.8-flash`    |
| `glm`                           | `openrouter/z-ai/glm-5.3`               |
| `kimi`                          | `openrouter/moonshotai/kimi-k3`         |
| `deepseek`                      | `openrouter/deepseek/deepseek-v4-pro`   |
| `minimax`                       | `openrouter/minimax/minimax-m3`         |
| `grok`                          | `openrouter/x-ai/grok-4.7`              |

Prefer to use the openrouter provider, when available there.

Note the vendor prefix within an openrouter ID is the **model vendor**, not a
pi provider name: OpenAI models are `openrouter/openai/...`. There is a
separate `openai-codex` pi provider whose models are bare IDs (`gpt-5.6-sol`,
no vendor prefix) — `openrouter/openai-codex/...` is never valid.

These IDs drift as models are released and retired, so **always verify before
launching** (step 1b) rather than trusting this table.

## Instructions

1. **Parse the arguments.**
   - Extract the reviewer model from `--model`/`-m` if present, resolving
     aliases via the table above. Otherwise use
     `openrouter/anthropic/claude-opus-5.5` (the `opus` alias).
   - Treat any remaining non-flag argument as the git revision `RANGE`.
   - **Generate a unique run ID** so parallel reviews never clash on shared
     `/tmp` paths. Use it as `REVIEW_ID` in every temp filename below:
     ```bash
     REVIEW_ID=$(uuidgen 2>/dev/null || od -An -N8 -tx1 /dev/urandom | tr -d ' \n')
     ```
     All the temp files in the steps that follow are named
     `/tmp/pi-review-<purpose>-$REVIEW_ID.*` — substitute the actual generated
     ID when you run the commands.

1b. **Verify the model resolves before launching.** A bad model ID fails inside
   the herdr/tmux pane, where the error is invisible to the agent. The agent
   just blocks on the done-file until it times out. Always check first.

   Split the resolved ID on its *first* `/` into pi provider + model, then
   confirm **both** that the provider is authenticated and that the model
   actually exists in that provider's catalog:
   ```bash
   # 1. provider auth (note: this validates ONLY the provider, never the model)
   pi auth check --provider <PROVIDER> --model <MODEL>   # want: "ready"

   # 2. model exists in that provider's catalog — this is the check that
   #    actually catches a wrong/stale model ID
   node -e "
   const s=require(process.env.HOME+'/.pi/agent/models-store.json');
   const [,p,...r]=process.argv; const m=r.join('/');
   const ids=new Set(((s[p]||{}).models||[]).map(x=>x.id||x.name));
   console.log(ids.has(m) ? 'model OK' : 'MODEL NOT FOUND in '+p);
   " '<PROVIDER>' '<MODEL>'
   ```
   `pi auth check` returns `ready` for *any* model string as long as the
   provider is authenticated — it will happily pass a nonexistent model — so
   the catalog check is not optional.

   If either check fails, do not launch. List the real IDs and pick the closest
   match:
   ```bash
   node -e "
   const s=require(process.env.HOME+'/.pi/agent/models-store.json');
   for (const [prov, v] of Object.entries(s))
     for (const m of v.models||[]) console.log(prov+'/'+(m.id||m.name));
   " | grep -iE '<pattern>'
   ```
   Configured providers are the keys of `~/.pi/agent/auth.json`; a provider
   missing from that file reports `invalid` regardless of model ID. Report the
   correction to the user rather than silently substituting a different model
   than they asked for.

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
   git diff <RANGE> --stat
   ```
   If the diff is empty, confirm the range is valid and inform the user.

4. **Save the diff** to a temp file (unique per run), excluding generated files
   so lockfile churn doesn't crowd out the real changes (a dependency bump can
   easily add thousands of `yarn.lock` lines and bury the diff, or blow the
   reviewer's context entirely):
   ```bash
   git diff <RANGE> -- . \
     ':(exclude)yarn.lock' ':(exclude)package-lock.json' \
     ':(exclude)pnpm-lock.yaml' ':(exclude)bun.lockb' \
     ':(exclude)*.snap' ':(exclude)**/generated/**' \
     > /tmp/pi-review-diff-$REVIEW_ID.md
   ```
   Mention any exclusions in the reviewer prompt so it knows the omission is
   deliberate and doesn't flag it as missing context. If a lockfile itself is
   the point of the review, keep it and say so.

5. **Run the reviewer subagent in a live herdr or tmux pane.** Write the prompt and a
   tiny runner script to temp files (this avoids nested-quoting problems when
   the prompt is long), then launch the full `pi` TUI in a detached split pane
   the user can watch in real time. Launching and waiting are two separate
   bash calls (step 5b): a review can take 10 to 30 minutes or more, and a
   wait that is a separate call can be started again if a bash timeout stops
   it.

   First write the prompt (note the diff path includes the run ID). The prompt
   tells the reviewer to write its report to the output file and then create a
   done-file as its final action — this is how the agent knows it finished,
   instead of scraping stdout:
   ```bash
   cat > /tmp/pi-review-prompt-$REVIEW_ID.txt <<EOF
   You are a senior engineer reviewing a code diff. The diff is at /tmp/pi-review-diff-$REVIEW_ID.md. Read it, then review it focusing ONLY on bugs, logic errors, security issues, missed edge cases, and opportunities to simplify/DRY the code. You have full access to the repository in the current working directory: read related files, trace callers, and run git commands as needed to understand the change in context. Do NOT modify repository files. Do NOT spawn subagents or start another review. Do NOT comment on style, naming, or minor preferences. For each finding, cite the file and line, explain the issue, give a severity (high/medium/low), and suggest a fix. Your report should be a numbered list, or say 'No issues found' if the code is clean. In both cases, append a short 'What I checked' section: the files you read, the callers you traced, and the commands or tests you ran.

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

   # This step only launches the reviewer. It prints REVIEW_ID and
   # REVIEW_PANE. Shell variables do not persist between bash calls, so copy
   # both values into the wait command of step 5b.
   if [ "${HERDR_ENV:-}" = 1 ]; then
     # Running inside herdr. Split the agent's own pane (--current resolves
     # to $HERDR_PANE_ID), not the pane that has UI focus. --no-focus keeps
     # the user's focus on this agent. --cwd keeps the reviewer in the repo.
     #
     # herdr splits only "right" or "down". Use the same aspect-ratio rule as
     # tmux below: cells are about twice as tall as wide.
     read -r PANE_W PANE_H < <(herdr pane layout --current \
       | jq -r --arg pane "$HERDR_PANE_ID" \
         '.result.layout.panes[] | select(.pane_id == $pane) | "\(.rect.width) \(.rect.height)"')
     if [ "$PANE_W" -gt "$((PANE_H * 2))" ]; then SPLIT_DIR=right; else SPLIT_DIR=down; fi
     # Read the new pane ID from the JSON response. Do not guess it.
     REVIEW_PANE=$(herdr pane split --current --direction "$SPLIT_DIR" \
       --cwd "$PWD" --no-focus | jq -r '.result.pane.pane_id')
     # The new pane starts a shell. "pane run" types the command and Enter.
     # "exec" replaces the shell, so the pane closes when the user quits pi
     # (the same as tmux). Keep the command short: on macOS herdr rejects a
     # command line longer than the terminal input limit. The runner script
     # reads the long prompt from its file, so the command stays short.
     herdr pane run "$REVIEW_PANE" "exec /tmp/pi-review-run-$REVIEW_ID.sh '<REVIEWER_MODEL>' '$REVIEW_ID'"
     echo "REVIEW_ID=$REVIEW_ID REVIEW_PANE=$REVIEW_PANE (herdr)"
   elif [ -n "$TMUX" ]; then
     # Running inside tmux: spawn a detached split pane (-d keeps the agent's
     # pane focused) so the user watches the live pi TUI without losing focus
     # on the conversation with this agent.
     #
     # Split RELATIVE TO THE AGENT'S OWN PANE, not the active pane. tmux sets
     # $TMUX_PANE to the unique ID of the pane each process runs in, and the
     # agent's bash inherits it. Without an explicit -t, split-window targets
     # whatever pane is currently active — which may be a different pane the
     # human focused for another task. Targeting $TMUX_PANE guarantees the new
     # pane appears next to this agent regardless of where focus is.
     AGENT_PANE="$TMUX_PANE"
     #
     # Pick the split direction from the agent pane's aspect ratio so each
     # pane stays as close to square as possible. Terminal cells are roughly
     # twice as tall as they are wide, so multiply the height (in cells) by 2
     # to compare visual extents. If the pane is visually wider than tall,
     # split side-by-side (-h); otherwise stack them top/bottom (-v).
     PANE_W=$(tmux display-message -t "$AGENT_PANE" -p '#{pane_width}')
     PANE_H=$(tmux display-message -t "$AGENT_PANE" -p '#{pane_height}')
     if [ "$PANE_W" -gt "$((PANE_H * 2))" ]; then SPLIT_DIR=-h; else SPLIT_DIR=-v; fi
     # -P -F prints the ID of the new pane, so that step 5b can check it.
     REVIEW_PANE=$(tmux split-window "$SPLIT_DIR" -d -P -F '#{pane_id}' -t "$AGENT_PANE" "/tmp/pi-review-run-$REVIEW_ID.sh '<REVIEWER_MODEL>' '$REVIEW_ID'")
     echo "REVIEW_ID=$REVIEW_ID REVIEW_PANE=$REVIEW_PANE (tmux)"
   else
     # Not in herdr or tmux: fall back to a non-interactive --print run. Interactive pi
     # expects a real TTY and never auto-exits after the first message, so the
     # agent's bash call would hang. -p/--print processes the prompt and exits;
     # the reviewer still writes its report to the output file and creates the
     # done-file as usual.
     # This run is synchronous: when it returns, the review is done. Skip
     # step 5b.
     pi --model '<REVIEWER_MODEL>' -p "$(cat /tmp/pi-review-prompt-$REVIEW_ID.txt)"
   fi
   ```
   The pane shows the live pi interface and stays open afterward.

5b. **Wait for the report (herdr and tmux).** Run this as its own bash call,
   with a long bash timeout (about 3600 s). Fill in the two values that step 5
   printed. If the call stops at its deadline or at a bash timeout, run it
   again: it continues to wait for the same review.
   ```bash
   REVIEW_ID=<REVIEW_ID>; REVIEW_PANE=<REVIEW_PANE>
   DONE=/tmp/pi-review-done-$REVIEW_ID
   DEADLINE=$(( $(date +%s) + 3300 ))
   MISSES=0
   # Check that the pane is still there. With "exec", the pane closes when pi
   # exits, so a closed pane without a done-file means pi quit before it
   # finished the review. A herdr call can fail for a short time, so accept
   # only "pane_not_found", 3 times in a row, as a closed pane.
   pane_gone() {
     if [ "${REVIEW_PANE#%}" != "$REVIEW_PANE" ]; then
       ! tmux display-message -t "$REVIEW_PANE" -p '#{pane_id}' >/dev/null 2>&1
     else
       herdr pane get "$REVIEW_PANE" 2>&1 >/dev/null | grep -q pane_not_found
     fi
   }
   while [ ! -f "$DONE" ] && [ "$(date +%s)" -lt "$DEADLINE" ]; do
     if pane_gone; then MISSES=$((MISSES + 1)); else MISSES=0; fi
     [ "$MISSES" -ge 3 ] && { echo "Reviewer pane closed before the review finished"; break; }
     sleep 5
   done
   if [ -f "$DONE" ]; then
     echo "Reviewer finished; report written to /tmp/pi-review-output-$REVIEW_ID.md"
   elif [ "$MISSES" -lt 3 ]; then
     echo "Still running at the deadline. Run this step again."
   fi
   ```

   **Diagnose a stuck review.** If the review seems stuck, look at the
   reviewer instead of waiting blindly. In herdr, read the pane. This works
   while pi is busy (only `herdr agent read` with `--lines` fails then):
   ```bash
   herdr pane read <REVIEW_PANE> --source recent-unwrapped --lines 80
   ```
   This shows errors and approval dialogs. herdr also detects pi in the pane,
   so you can follow its tool calls in its pi session log:
   ```bash
   herdr pane get <REVIEW_PANE> | jq -r '.result.pane.agent_session.value'   # a .jsonl file
   ```
   Report what you see to the user. Do not answer reviewer dialogs or close
   the pane without the user's consent. If the wait reports that the pane
   closed, pi exited without a report (the user quit it, or it crashed). Tell
   the user. Do not relaunch automatically. In tmux there is no equivalent
   read step in this skill, so ask the user to look at the pane.

   If the report says "No issues found" and has no "What I checked" section,
   be careful with it. Ask the reviewer (in its pane) what it checked before
   you rely on it.

6. **Present the findings** (read them from `/tmp/pi-review-output-$REVIEW_ID.md`) to the user, then ask whether they'd like you to
   address any of them.

## Notes

- The default reviewer model is `openrouter/anthropic/claude-opus-5.5` (the
  `opus` alias), used for deep code analysis. Override it per-invocation with
  `--model`.
- Model IDs in the alias table go stale as models ship and retire. Step 1b
  verifies the resolved ID with `pi auth check` before launching, because a bad
  ID otherwise fails silently inside the herdr/tmux pane and the agent just blocks on
  the done-file until it times out.
- Inside herdr or tmux, the subagent runs the **full interactive `pi` TUI** (not
  `--print`), so the user sees its live progress (thinking, tool calls, file
  reads) stream in the pane. Outside both it falls back to non-interactive
  `-p`/`--print` mode (see below). The reviewer is instructed to write its report to
  `/tmp/pi-review-output-$REVIEW_ID.md` and then `touch` a done-file as its
  final action; the agent never scrapes stdout.
- All temp files are namespaced with a per-invocation random `REVIEW_ID`
  (`/tmp/pi-review-*-$REVIEW_ID.*`), so multiple reviews can run in parallel
  without clobbering each other's diff, prompt, output, or done-file.
- When invoked inside tmux, the reviewer runs in a detached split pane so the
  user can watch the live pi TUI without losing focus on the conversation with
  this agent. The split is created relative to the agent's own pane (via
  `$TMUX_PANE`, the pane ID the agent's process inherits), not the currently
  active pane — so the reviewer always appears next to this agent even if the
  human has focused a different pane for another task. The split direction
  adapts to the agent pane's aspect ratio
  (accounting for cells being ~twice as tall as wide): side-by-side (`-h`) when
  the pane is wider than tall, stacked (`-v`) otherwise, keeping both panes
  close to square. The agent blocks (polling `/tmp/pi-review-done-$REVIEW_ID`)
  until the reviewer writes its done-file, then reads the report from
  `/tmp/pi-review-output-$REVIEW_ID.md`. Because it is the real interactive
  interface, the pane stays open after the review for the user to scroll, ask
  follow-ups, or close themselves. Outside herdr and tmux there is no pane to
  watch, so the reviewer runs non-interactively via `-p`/`--print` (the interactive TUI
  expects a real TTY and never auto-exits after the first message, which would
  hang the agent's bash call); the reviewer still writes its report to the
  output file and creates the done-file.
- Inside herdr, the behavior matches tmux with these differences. The split
  targets the agent's own pane via `--current` (`$HERDR_PANE_ID`). The split
  direction is `right` or `down` (herdr's names for tmux `-h` and `-v`).
  `--no-focus` keeps the user's focus on this agent. The new pane starts a
  shell, and `herdr pane run` sends `exec <runner>` to it, so the pane closes
  when the user quits pi (the same as tmux). Do not close the pane from the
  agent: the user owns it after the review. The agent can read the pane with
  `herdr pane read` to diagnose a stuck review. The herdr path needs `jq` to
  parse herdr's JSON output.
- The reviewer uses `pi` through a plain pane (`herdr pane run`), not
  `herdr agent start` / `herdr agent prompt`. The done-file protocol already
  signals completion in all three modes, so one mechanism covers all of them.
- The subagent runs in the current working directory and has full tool access,
  so it can read any file, trace callers, and run git commands to understand
  the change in its broader context — it is not limited to the diff alone.
- Findings about pre-existing code outside the diff should be noted but
  flagged as out-of-scope.
