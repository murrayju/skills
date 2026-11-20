#!/usr/bin/env bash
# Usage: close-panes.sh [TICKET]
# Close the panes that this run made: the implementer pane in
# $PR_WORK/<TICKET>-pane and the reviewer panes in $PR_WORK/<TICKET>-reviews.tsv.
# Without TICKET, close the recorded panes of all tickets.
# Do not close other panes. The user can have panes of their own in the same
# workspace.
source "$(dirname "$0")/common.sh"
PATTERN="${1:-*}"
for f in "$PR_WORK"/$PATTERN-pane "$PR_WORK"/$PATTERN-reviews.tsv; do
  [ -f "$f" ] || continue
  case "$f" in *.tsv) panes=$(cut -f4 "$f") ;; *) panes=$(cat "$f") ;; esac
  for p in $panes; do
    case "$p" in ""|"-"|sub:*|"${HERDR_PANE_ID:-}") continue ;; esac
    if herdr pane close "$p" >/dev/null 2>&1; then echo "closed $p"; fi
  done
  # Keep the review log: review-summary.sh reads it.
  case "$f" in *.tsv) ;; *) rm -f "$f" ;; esac
done
