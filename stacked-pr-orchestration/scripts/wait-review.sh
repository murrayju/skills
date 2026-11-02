#!/usr/bin/env bash
# Usage: wait-review.sh <TICKET> [MAX_MINUTES]
# Wait for the reviewer report of the ticket, then print it. Stop if the
# reviewer pane closes before the report (pi exited). Run it again if it stops
# at MAX_MINUTES.
source "$(dirname "$0")/common.sh"
ID=$(read_file "$STACK_WORK/$1-review-id") || exit 1
PANE=$(read_file "$STACK_WORK/$1-review-pane") || exit 1
R="$STACK_WORK/review"; MAX="${2:-55}"; misses=0
for _ in $(seq 1 $(( MAX * 12 ))); do
  [ -f "$R/$ID-done" ] && break
  # A closed pane counts only after 3 checks in a row.
  if pane_gone "$PANE"; then misses=$((misses + 1)); else misses=0; fi
  [ "$misses" -ge 3 ] && { echo "reviewer pane $PANE closed before the report"; exit 1; }
  sleep 5
done
[ -f "$R/$ID-done" ] || { echo "review not done after $MAX minutes (run again to keep waiting)"; exit 3; }
read_file "$R/$ID-output.md"
