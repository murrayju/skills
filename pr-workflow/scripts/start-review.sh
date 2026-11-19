#!/usr/bin/env bash
# Usage: start-review.sh <TICKET> <BASE_REF>
# Start the next review round in a pane below the ticket pane, the same way as
# the review skill. It reviews BASE_REF...HEAD and writes a report file.
# Round N uses the reviewer at position (N-1) modulo the count in
# REVIEWER_MODELS, so a pass runs every reviewer once, in order. Each round
# gets the earlier reports and the PR feedback (if they exist), so that it
# checks the fixes and does not repeat them.
# Each round is one line in $PR_WORK/<TICKET>-reviews.tsv:
#   round, model, id, pane, reviewed HEAD.
# The reviewers use only their own model: the Advisor tools are excluded.
# Start it only after the implementer is done: an empty diff wastes a review.
source "$(dirname "$0")/common.sh"
set -euo pipefail
TICKET="$1"; BASE="$2"
LOG="$PR_WORK/$TICKET-reviews.tsv"; touch "$LOG"
ROUND=$(( $(wc -l < "$LOG") + 1 ))
read -ra REVIEWERS <<< "$REVIEWER_MODELS"
MODEL="${REVIEWERS[$(( (ROUND - 1) % ${#REVIEWERS[@]} ))]}"
[ -n "$(git diff --stat "$BASE...HEAD")" ] || { echo "empty diff $BASE...HEAD"; exit 1; }
ID="$TICKET-r$ROUND-$(date +%s)"; R="$PR_WORK/review"
git diff "$BASE...HEAD" -- . ':(exclude)yarn.lock' ':(exclude)package-lock.json' ':(exclude)pnpm-lock.yaml' \
  ':(exclude)*.snap' ':(exclude)**/generated/**' > "$R/$ID-diff.md"
git log --oneline "$BASE..HEAD" > "$R/$ID-log.txt"
EARLIER=""
while IFS=$'\t' read -r prev_round _ prev_id _ _; do
  [ -f "$R/$prev_id-output.md" ] && EARLIER="$EARLIER Review round $prev_round report: $R/$prev_id-output.md."
done < "$LOG"
[ -s "$PR_WORK/$TICKET-feedback.md" ] && EARLIER="$EARLIER PR feedback (automated review and people): $PR_WORK/$TICKET-feedback.md."
[ -n "$EARLIER" ] && EARLIER="This is review round $ROUND.$EARLIER The findings in these files were addressed in later commits, fixed or answered. Check that the fixes are correct, do not repeat findings that are already addressed, and look for what the earlier reviews missed."
cat > "$R/$ID-prompt.txt" <<P
You are a senior engineer reviewing a code diff for ticket $TICKET (ticket text: $PR_WORK/$TICKET.md, planned PR description: $PR_WORK/$TICKET-pr.md). The diff is at $R/$ID-diff.md (lockfiles, snapshots and generated files are excluded on purpose; run git diff $BASE...HEAD -- <file> if you need them). Commits: $R/$ID-log.txt. $EARLIER Review it focusing ONLY on bugs, logic errors, security issues, missed edge cases, regressions in runtime behavior, gaps in the new test coverage, and opportunities to simplify/DRY the code. You have full access to the repository in the current working directory (the branch is checked out): read related files, trace callers, and run git commands and targeted tests. Do NOT modify repository files and do NOT commit. Do NOT spawn subagents. Do NOT comment on style, naming, or minor preferences. For each finding, cite the file and line, explain the issue, give a severity (high/medium/low), and suggest a fix. Use a numbered list, or say 'No issues found'. Note pre-existing problems outside the diff as out-of-scope (do not count them). Append a short "What I checked" section (files, commands, callers traced). The LAST line of the report must be exactly: FINDINGS: high=<n> medium=<n> low=<n>

IMPORTANT: WRITE the full report to $R/$ID-output.md with your file-writing tool. Then, as your VERY LAST action, run: touch $R/$ID-done
P
TICKET_PANE=$(read_file "$PR_WORK/$TICKET-pane")
PANE=$(herdr pane split --pane "$TICKET_PANE" --direction down --cwd "$REPO" --no-focus | jq -r .result.pane.pane_id)
printf '%s\t%s\t%s\t%s\t%s\n' "$ROUND" "$MODEL" "$ID" "$PANE" "$(git rev-parse --short HEAD)" >> "$LOG"
# The same launch as the review skill: pi with the prompt as its first message.
# Exclude the Advisor tools: the reviewer uses only its own model.
launch_pi "$PANE" "$MODEL" "$R/$ID-prompt.txt" --exclude-tools "$ADVISOR_TOOLS"
wait_working "$PANE" || exit 1
echo "round $ROUND: $MODEL, id $ID"
