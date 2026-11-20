#!/usr/bin/env bash
# Usage: wait-review.sh <TICKET> [MAX_MINUTES]
# Wait for the report of the latest review round of the ticket, then print
# it. Stop if the reviewer pane closes before the report (pi exited). Run it
# again if it stops at MAX_MINUTES.
source "$(dirname "$0")/common.sh"
LAST=$(tail -1 "$PR_WORK/$1-reviews.tsv" 2>/dev/null)
[ -n "$LAST" ] || { echo "no review round in $PR_WORK/$1-reviews.tsv"; exit 1; }
ID=$(echo "$LAST" | cut -f3); PANE=$(echo "$LAST" | cut -f4)
case "$PANE" in
  ""|"-"|sub:*) echo "round $ID uses herdr_subagent ($PANE), not a manual pane: use herdr_subagent wait" >&2; exit 1 ;;
esac
R="$PR_WORK/review"; MAX="${2:-55}"; misses=0
for _ in $(seq 1 $(( MAX * 12 ))); do
  [ -f "$R/$ID-done" ] && break
  # A closed pane counts only after 3 checks in a row.
  if pane_gone "$PANE"; then misses=$((misses + 1)); else misses=0; fi
  [ "$misses" -ge 3 ] && { echo "reviewer pane $PANE closed before the report"; exit 1; }
  sleep 5
done
[ -f "$R/$ID-done" ] || { echo "review not done after $MAX minutes (run again to keep waiting)"; exit 3; }
read_file "$R/$ID-output.md"
