---
name: review
description: Run a focused code review using a stronger subagent model, with no Advisor. By default reviews the current branch (all commits since it diverged from the default branch) for bugs, logic errors, security issues, and missed edge cases. Supports a custom revision range and a selectable reviewer model. Invoke via /skill:review, /skill:review main..HEAD, or /skill:review --model gpt-5.5.
---

# Code Review via Subagent

Launches a fresh interactive `pi` session on `<REVIEWER_MODEL>` to get a second
opinion on code changes from a stronger model. Prefer the `herdr_subagent` tool
(from `murrayju/pi-herdr-subagents`), which runs the reviewer in a named Herdr
tab and reports completion directly without signal files. When `herdr_subagent`
is not installed, fall back to a manual Herdr/tmux pane or `pi -p`.

The reviewer uses ONLY the selected model. Always disable the Advisor: pass
`advisor: false` to `herdr_subagent`, or `--exclude-tools ask_advisor,record_advisor_outcome`
in fallback launches. That removes the `ask_advisor` tool, Advisor prompt rules,
and automatic gates, and the global `advisorToolsEnabled` setting cannot add
them back. The prompt also forbids subagents. Keep both when you edit this skill.

### Launch mode

Pick the first mode that is available:

| Check                    | Mode                                                                 |
| ------------------------ | -------------------------------------------------------------------- |
| `herdr_subagent` tool    | **preferred**: named Herdr tab via `herdr_subagent` (no signal files) |
| `"$HERDR_ENV" = 1`       | fallback: manual Herdr split pane (`$HERDR_PANE_ID`) + done-file     |
| `-n "$TMUX"`             | fallback: manual tmux split pane (`$TMUX_PANE`) + done-file          |
| neither                  | fallback: non-interactive `pi -p` in the agent's own shell           |

## Usage

```
/skill:review                          # Review the current branch vs the default branch
/skill:review HEAD~3..HEAD             # Review a specific revision range
/skill:review main..HEAD               # Review all changes vs main
/skill:review --model gpt-5.5          # Review the current branch with a specific model
/skill:review main..HEAD --model gpt-5.5   # Both
```

Arguments (any order, all optional):

- **`--model <name>` / `-m <name>`**: the reviewer model, named any way the
  user likes: `opus`, `gpt 6.1 sol`, `gemini flash`, or a full
  `provider/model` ID. Defaults to `opus`, which is the newest Claude Opus on
  the preferred provider (today `concentrate/claude-opus-5-5`).
- **Any other argument**: a git revision range. If omitted, defaults to the
  current branch (see below).

### Choosing the reviewer model

Keep no list of model IDs here: they drift as models ship and retire. Resolve
the name against the live catalog instead, with the resolver script this skill
links from the shared `scripts/` folder:

```bash
~/.agents/skills/review/scripts/resolve-model.sh "<what the user typed>"   # best 3, best first
```

It prints full `provider/model` IDs, best first, using the ranks below. Take
the first line. No output with exit 0 means that no model matches; a non-zero
exit means that the catalog could not be read, which you report to the user
instead of guessing.

1. **An exact ID wins.** If the user typed a full ID that exists, the script
   returns it unchanged. In an openrouter ID the part after the provider is
   the model **vendor**, not a pi provider: OpenAI models are
   `openrouter/openai/...`, and `openrouter/openai-codex/...` never exists.
2. **Then the provider.** `concentrate` first, `openrouter` second, and every
   other provider last.
3. **Then the generation.** The first run of numbers in the name is the
   version (`gpt-6.1-sol` is 6.1, `claude-opus-5-5` is 5.5), and the highest
   version wins, so `opus` gives the newest Claude Opus. A date suffix counts
   as part of the version, so of two snapshots of one model the newer date
   wins: `deepseek-v4-flash-0731` beats `deepseek-v4-flash-0423`.
4. **Then the shortest name**, which is the base model and not a `-pro`
   variant or a `-highspeed` clone.

Matching ignores case, treats `.` and `-` as the same character, and needs
only part of the name, so `claude-opus-5.5`, `gemini flash` and `kimi k3` all
match. It skips `:batch`, `:free` and `~latest` IDs.

Do not let `pi` resolve the name at launch. It does resolve a short name, but
it takes the first catalog match, which today is a Bedrock ID
(`us.openai.gpt-6.1-sol`), so the provider preference is lost.

If the script prints nothing, nothing matches: show the user
`pi --list-models` and ask which model they meant. If the first line is the
wrong variant of what the user named (they said `gemini` and got
`gemini-4-argon`), use a more specific name or take another printed line. Tell
the user which ID you picked.

## Instructions

1. **Parse the arguments.**
   - Extract the reviewer model from `--model`/`-m` if present and resolve it
     with `~/.agents/skills/review/scripts/resolve-model.sh` (see "Choosing the
     reviewer model"). Otherwise resolve `opus`.
   - Treat any remaining non-flag argument as the git revision `RANGE`.
   - **Generate a unique run ID** so parallel reviews never clash on shared
     `/tmp` paths. Use it as `REVIEW_ID` in every temp filename below:
     ```bash
     REVIEW_ID=$(uuidgen 2>/dev/null || od -An -N8 -tx1 /dev/urandom | tr -d ' \n')
     ```
     All the temp files in the steps that follow are named
     `/tmp/pi-review-<purpose>-$REVIEW_ID.*` — substitute the actual generated
     ID when you run the commands.

1b. **Verify the model exists and the provider is ready.** A bad model ID
   either fails validation in `herdr_subagent` or fails silently inside a
   fallback pane. Check first.

   Confirm that the ID is in the live catalog, spelled exactly. An exact ID
   ranks first, so the resolver returns it unchanged when it exists:
   ```bash
   [ "$(~/.agents/skills/review/scripts/resolve-model.sh '<MODEL>' 1)" = '<MODEL>' ] \
     || { echo "MODEL NOT FOUND: <MODEL>"; exit 1; }
   ```
   Then confirm that the provider can serve it. Split the resolved ID on its
   *first* `/` into provider and model; the rest of the ID, slashes included,
   is the model:
   ```bash
   pi auth check --provider <PROVIDER> --model <MODEL>   # want: "ready"
   ```
   Note that `pi auth check` answers `ready` for any model string, existing or
   not, so the exact-ID check above is not optional.

   If either check fails, do not launch. Report it to the user rather than
   silently substituting a different model than they asked for.

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

5. **Run the reviewer subagent (preferred: `herdr_subagent`).** Remove any
   stale output file first:
   ```bash
   rm -f /tmp/pi-review-output-$REVIEW_ID.md
   ```
   Call `herdr_subagent` with `action: "start"`:
   - `name`: `"review"` (or `"review-<short-model>"`, one line, max 64 chars)
   - `model`: the exact resolved `<REVIEWER_MODEL>` (`provider/model`)
   - `advisor`: `false`
   - `cwd`: the repository working directory (`$PWD`)
   - `prompt`:
     > You are a senior engineer reviewing a code diff. The diff is at `/tmp/pi-review-diff-<REVIEW_ID>.md`. Read it, then review it focusing ONLY on bugs, logic errors, security issues, missed edge cases, and opportunities to simplify/DRY the code. You have full access to the repository in the current working directory: read related files, trace callers, and run git commands as needed to understand the change in context. Do NOT modify repository files. Do NOT spawn subagents or start another review: use only your own model. Do NOT comment on style, naming, or minor preferences. For each finding, cite the file and line, explain the issue, give a severity (high/medium/low), and suggest a fix. Your report should be a numbered list, or say 'No issues found' if the code is clean. In both cases, append a short 'What I checked' section: the files you read, the callers you traced, and the commands or tests you ran.
     >
     > IMPORTANT: WRITE the full report to `/tmp/pi-review-output-<REVIEW_ID>.md` using your file-writing tool (long replies can be truncated in tool output), then finish with a brief summary.

   Then wait for completion with `herdr_subagent`:
   - Call `{ action: "wait", id: "<worker-id>", timeoutSeconds: 600 }`.
   - If the result has `"timedOut": true`, call `wait` again. Do NOT call
     `start` or `send` again: a timeout stops only the wait, not the worker.
   - Check the settled `status`:
     - `completed`: confirm `/tmp/pi-review-output-$REVIEW_ID.md` exists and is
       non-empty. (`completed` means Pi finished responding, not that the file
       was written.) If the file is missing, check `output` from `wait` or call
       `herdr_subagent({ action: "send", id, prompt: "Write the full report to /tmp/pi-review-output-<REVIEW_ID>.md." })`
       once idle and `wait` again. If the report says "No issues found" with no
       "What I checked" section, follow up with `send` + `wait` before relying
       on it.
     - `blocked`: tell the user to open the reviewer tab (click the card or run
       `/subagents <id>`) to answer its prompt. Do not answer dialogs for them.
     - `failed`, `aborted`, or `disconnected`: report `output` and
       `sessionFile` to the user. Do not relaunch automatically.
   - Leave the reviewer tab open afterward so the user can inspect it or follow
     up; do not call `close` without the user's consent.

5b. **Fallback when `herdr_subagent` is not installed.** Use the same prompt
   text, appending:
   `Then, as your VERY LAST action, run: touch /tmp/pi-review-done-<REVIEW_ID>. Only create the done-file after the report file has been fully written.`
   Remove stale `/tmp/pi-review-output-$REVIEW_ID.md` and
   `/tmp/pi-review-done-$REVIEW_ID`, write the prompt to
   `/tmp/pi-review-prompt-$REVIEW_ID.txt`, and create an executable runner
   script `/tmp/pi-review-run-$REVIEW_ID.sh`:
   ```bash
   #!/usr/bin/env bash
   exec pi --model "$1" --exclude-tools ask_advisor,record_advisor_outcome "$(cat /tmp/pi-review-prompt-$2.txt)"
   ```
   Pass the prompt as a positional message (not `-p`) so interactive `pi` stays
   open in the pane. Launch according to the environment:
   - **Herdr (`HERDR_ENV=1`):** split your own pane (`herdr pane split --current --direction right --cwd "$PWD" --no-focus`, or `down` if narrow), read `.result.pane.pane_id`, and run `herdr pane run "$REVIEW_PANE" "exec /tmp/pi-review-run-$REVIEW_ID.sh '<REVIEWER_MODEL>' '$REVIEW_ID'"`.
   - **tmux (`-n "$TMUX"`):** `REVIEW_PANE=$(tmux split-window -h -d -P -F '#{pane_id}' -t "$TMUX_PANE" "/tmp/pi-review-run-$REVIEW_ID.sh '<REVIEWER_MODEL>' '$REVIEW_ID'")` (or `-v` if narrow).
   - **Neither:** run synchronously with `pi --model '<REVIEWER_MODEL>' --exclude-tools ask_advisor,record_advisor_outcome -p "$(cat /tmp/pi-review-prompt-$REVIEW_ID.txt)"` (no polling needed).

   In Herdr or tmux, wait in a separate long bash call by polling every 5s for
   `/tmp/pi-review-done-$REVIEW_ID`. Stop early if the pane closes (in Herdr,
   count it closed only after 3 consecutive `pane_not_found` errors from
   `herdr pane get "$REVIEW_PANE"`). To inspect a stuck Herdr pane, run
   `herdr pane read "$REVIEW_PANE" --source recent-unwrapped --lines 80`. Do
   not close the pane.

6. **Present the findings** (read them from `/tmp/pi-review-output-$REVIEW_ID.md`) to the user, then ask whether they'd like you to
   address any of them.

## Notes

- The default reviewer model is `opus`, which resolves to the newest Claude
  Opus on the preferred provider (today `concentrate/claude-opus-5-5`), used
  for deep code analysis. Override it per-invocation with `--model`.
- The reviewer never uses the Advisor, even when it is enabled globally in
  `~/.pi/agent/advisor.json`: `herdr_subagent` passes `advisor: false`, and
  the fallback paths pass `--exclude-tools ask_advisor,record_advisor_outcome`.
- `~/.agents/skills/review/scripts/resolve-model.sh` reads the live catalog
  from `pi --list-models` on every call, so it never goes stale. Step 1b then
  checks that the provider is ready with `pi auth check`, because a bad ID
  otherwise fails inside the worker tab/pane.
- Writing the full report to `/tmp/pi-review-output-$REVIEW_ID.md` avoids
  truncation (the `herdr_subagent` tool truncates `output` at 200 lines or
  16 KiB) and works across both the extension and fallback modes. All temp
  files include a unique `REVIEW_ID` so parallel reviews do not clash.
- `herdr_subagent` inherits the parent session's thinking level and runs in a
  named background tab with live usage tracking and a clickable card. The
  reviewer tab stays open after the review so the user can scroll or follow up.
- The subagent runs in the current working directory and has full tool access,
  so it can read any file, trace callers, and run git commands to understand
  the change in its broader context, not just the diff.
- Findings about pre-existing code outside the diff should be noted and
  flagged as out-of-scope.
