#!/usr/bin/env bash
# Usage: review-summary.sh <TICKET> [--update-pr]
# Print a table with one line for each review round of the ticket: the
# reviewer and the count of findings by severity (from the "FINDINGS:" line
# at the end of the report). "?" means that the report has no such line:
# read the report and count the findings yourself.
# With --update-pr, also put the table under the "## Reviews" heading of
# $PR_WORK/<TICKET>-pr.md. If there is no such heading, add the section
# before the "Closes" line, or at the end.
source "$(dirname "$0")/common.sh"
T="$1"; LOG="$PR_WORK/$T-reviews.tsv"
[ -s "$LOG" ] || { echo "no review rounds in $LOG"; exit 1; }
count() { echo "$line" | grep -oE "$1=[0-9]+" | cut -d= -f2 || true; }
TABLE=$(
  echo "| round | reviewer | high | medium | low |"
  echo "| -- | -- | -- | -- | -- |"
  while IFS=$'\t' read -r round model id _ _; do
    line=$(grep -E '^FINDINGS: ' "$PR_WORK/review/$id-output.md" 2>/dev/null | tail -1)
    h=$(count high); m=$(count medium); l=$(count low)
    echo "| $round | ${model#*/} | ${h:-?} | ${m:-?} | ${l:-?} |"
  done < "$LOG"
)
echo "$TABLE"
[ "${2:-}" = --update-pr ] || exit 0
PR_FILE="$PR_WORK/$T-pr.md"
read_file "$PR_FILE" >/dev/null || exit 1
# Replace the body of "## Reviews" (up to the next heading or "Closes" line).
# Without the heading, insert the section before "Closes", or at the end.
TABLE="$TABLE" awk '
  function section() { print "## Reviews\n"; print ENVIRON["TABLE"]; print ""; done = 1 }
  /^## Reviews[[:space:]]*$/ { section(); skip = 1; next }
  skip && /^(#|Closes )/ { skip = 0 }
  skip { next }
  !done && /^Closes / { section() }
  { print }
  END { if (!done) { print ""; section() } }
' "$PR_FILE" > "$PR_FILE.tmp" && mv "$PR_FILE.tmp" "$PR_FILE"
echo "updated: $PR_FILE"
