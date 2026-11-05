#!/usr/bin/env bash
# Usage: start-review.sh <TICKET> <BASE_REF> <ROUND>
# Start a reviewer in a pane below the ticket pane, the same way as the review
# skill. It reviews BASE_REF...HEAD and writes a report file.
# ROUND 1 uses REVIEWER_MODEL_1 (before the PR opens). ROUND 2 uses
# REVIEWER_MODEL_2 (after the round 1 fixes; it also gets the round 1 report
# and the automated PR review, if they exist, so that it checks the fixes and
# does not repeat them).
# The reviewers use only their own model: the Advisor tools are excluded.
# Start it only after the implementer is done: an empty diff wastes a review.
source "$(dirname "$0")/common.sh"
set -euo pipefail
TICKET="$1"; BASE="$2"; ROUND="${3:-}"
case "$ROUND" in 1|2) ;; *) echo "ROUND must be 1 or 2"; exit 1 ;; esac
MODEL_VAR="REVIEWER_MODEL_$ROUND"; MODEL="${!MODEL_VAR:-}"
[ -n "$MODEL" ] || { echo "$MODEL_VAR is not set in $STACK_WORK/config.env"; exit 1; }
[ -n "$(git diff --stat "$BASE...HEAD")" ] || { echo "empty diff $BASE...HEAD"; exit 1; }
ID="$TICKET-r$ROUND-$(date +%s)"; R="$STACK_WORK/review"
git diff "$BASE...HEAD" -- . ':(exclude)yarn.lock' ':(exclude)package-lock.json' ':(exclude)pnpm-lock.yaml' \
  ':(exclude)*.snap' ':(exclude)**/generated/**' > "$R/$ID-diff.md"
git log --oneline "$BASE..HEAD" > "$R/$ID-log.txt"
EARLIER=""
if [ "$ROUND" = 2 ]; then
  R1_ID=$(cat "$STACK_WORK/$TICKET-review-id-1" 2>/dev/null || true)
  [ -n "$R1_ID" ] && [ -f "$R/$R1_ID-output.md" ] && EARLIER="$EARLIER Review round 1 report (its findings were addressed in later commits): $R/$R1_ID-output.md."
  [ -s "$STACK_WORK/$TICKET-claude-review.md" ] && EARLIER="$EARLIER Automated PR review: $STACK_WORK/$TICKET-claude-review.md and $STACK_WORK/$TICKET-claude-inline.md."
  [ -n "$EARLIER" ] && EARLIER="This is review round 2.$EARLIER Check that those findings are really fixed, do not repeat findings that are already addressed, and look for what the earlier reviews missed."
fi
cat > "$R/$ID-prompt.txt" <<P
You are a senior engineer reviewing a code diff for ticket $TICKET (ticket text: $STACK_WORK/$TICKET.md, planned PR description: $STACK_WORK/$TICKET-pr.md). The diff is at $R/$ID-diff.md (lockfiles, snapshots and generated files are excluded on purpose; run git diff $BASE...HEAD -- <file> if you need them). Commits: $R/$ID-log.txt. $EARLIER Review it focusing ONLY on bugs, logic errors, security issues, missed edge cases, regressions in runtime behavior, gaps in the new test coverage, and opportunities to simplify/DRY the code. You have full access to the repository in the current working directory (the branch is checked out): read related files, trace callers, and run git commands and targeted tests. Do NOT modify repository files and do NOT commit. Do NOT spawn subagents. Do NOT comment on style, naming, or minor preferences. For each finding, cite the file and line, explain the issue, give a severity (high/medium/low), and suggest a fix. Use a numbered list, or say 'No issues found'. Note pre-existing problems outside the diff as out-of-scope. Append a short "What I checked" section (files, commands, callers traced).

IMPORTANT: WRITE the full report to $R/$ID-output.md with your file-writing tool. Then, as your VERY LAST action, run: touch $R/$ID-done
P
TICKET_PANE=$(read_file "$STACK_WORK/$TICKET-pane")
PANE=$(herdr pane split --pane "$TICKET_PANE" --direction down --cwd "$REPO" --no-focus | jq -r .result.pane.pane_id)
# The latest review (read by wait-review.sh), and the review of this round.
echo "$PANE" > "$STACK_WORK/$TICKET-review-pane"
echo "$ID" > "$STACK_WORK/$TICKET-review-id"
echo "$PANE" > "$STACK_WORK/$TICKET-review-pane-$ROUND"
echo "$ID" > "$STACK_WORK/$TICKET-review-id-$ROUND"
# The same launch as the review skill: pi with the prompt as its first message.
# Exclude the Advisor tools: the reviewer uses only its own model.
launch_pi "$PANE" "$MODEL" "$R/$ID-prompt.txt" --exclude-tools "$ADVISOR_TOOLS"
wait_working "$PANE" || exit 1
echo "$ID ($MODEL)"
