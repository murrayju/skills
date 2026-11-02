#!/usr/bin/env bash
# Usage: close-panes.sh [TICKET]
# Close the panes that this run made: the panes recorded in
# $STACK_WORK/<TICKET>-pane and $STACK_WORK/<TICKET>-review-pane. Without
# TICKET, close the recorded panes of all tickets.
# Do not close other panes. The user can have panes of their own in the same
# workspace.
source "$(dirname "$0")/common.sh"
PATTERN="${1:-*}"
for f in "$STACK_WORK"/$PATTERN-pane "$STACK_WORK"/$PATTERN-review-pane; do
  [ -f "$f" ] || continue
  p=$(cat "$f")
  [ -n "$p" ] && [ "$p" != "$HERDR_PANE_ID" ] || continue
  if herdr pane close "$p" >/dev/null 2>&1; then echo "closed $p"; fi
  rm -f "$f"
done
