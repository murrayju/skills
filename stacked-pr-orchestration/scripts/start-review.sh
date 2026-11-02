#!/usr/bin/env bash
# Usage: start-review.sh <TICKET> <BASE_REF>
# Start the second-opinion reviewer (REVIEWER_MODEL) in a pane below the
# ticket pane. It reviews BASE_REF...HEAD and writes a report file.
# Start it only after the implementer is done: an empty diff wastes a review.
source "$(dirname "$0")/common.sh"
set -euo pipefail
TICKET="$1"; BASE="$2"
[ -n "$(git diff --stat "$BASE...HEAD")" ] || { echo "empty diff $BASE...HEAD"; exit 1; }
ID="$TICKET-$(date +%s)"; R="$STACK_WORK/review"
git diff "$BASE...HEAD" -- . ':(exclude)yarn.lock' ':(exclude)package-lock.json' ':(exclude)pnpm-lock.yaml' \
  ':(exclude)*.snap' ':(exclude)**/generated/**' > "$R/$ID-diff.md"
git log --oneline "$BASE..HEAD" > "$R/$ID-log.txt"
cat > "$R/$ID-prompt.txt" <<P
You are a senior engineer reviewing a code diff for ticket $TICKET (ticket text: $STACK_WORK/$TICKET.md, planned PR description: $STACK_WORK/$TICKET-pr.md). The diff is at $R/$ID-diff.md (lockfiles, snapshots and generated files are excluded on purpose; run git diff $BASE...HEAD -- <file> if you need them). Commits: $R/$ID-log.txt. Review it focusing ONLY on bugs, logic errors, security issues, missed edge cases, regressions in runtime behavior, gaps in the new test coverage, and opportunities to simplify/DRY the code. You have full access to the repository in the current working directory (the branch is checked out): read related files, trace callers, and run git commands and targeted tests. Do NOT modify repository files and do NOT commit. Do NOT spawn subagents. Do NOT comment on style, naming, or minor preferences. For each finding, cite the file and line, explain the issue, give a severity (high/medium/low), and suggest a fix. Use a numbered list, or say 'No issues found'. Note pre-existing problems outside the diff as out-of-scope. Append a short "What I checked" section (files, commands, callers traced).

IMPORTANT: WRITE the full report to $R/$ID-output.md with your file-writing tool. Then, as your VERY LAST action, run: touch $R/$ID-done
P
TICKET_PANE=$(read_file "$STACK_WORK/$TICKET-pane")
PANE=$(herdr pane split --pane "$TICKET_PANE" --direction down --cwd "$REPO" --no-focus | jq -r .result.pane.pane_id)
echo "$PANE" > "$STACK_WORK/$TICKET-review-pane"
herdr agent start "rev-${TICKET,,}" --kind pi --pane "$PANE" --timeout 120000 -- --model "$REVIEWER_MODEL" --thinking "$THINKING" >/dev/null || true
"$SKILL_SCRIPTS/prompt.sh" "$PANE" "@$R/$ID-prompt.txt" >/dev/null
echo "$ID" > "$STACK_WORK/$TICKET-review-id"
echo "$ID"
