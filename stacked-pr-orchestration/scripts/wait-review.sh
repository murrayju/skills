#!/usr/bin/env bash
# Usage: wait-review.sh <TICKET> [MAX_MINUTES]
# Wait for the reviewer report of the ticket, then print it.
source "$(dirname "$0")/common.sh"
ID=$(read_file "$STACK_WORK/$1-review-id") || exit 1
R="$STACK_WORK/review"; MAX="${2:-55}"
for _ in $(seq 1 $(( MAX * 6 ))); do [ -f "$R/$ID-done" ] && break; sleep 10; done
[ -f "$R/$ID-done" ] || { echo "review not done after $MAX minutes"; exit 3; }
read_file "$R/$ID-output.md"
