#!/usr/bin/env bash
# Usage: close-panes.sh
# Close all panes of this herdr workspace except the pane of the orchestrator.
# Use it only for panes that this run made.
herdr pane list --workspace "$HERDR_WORKSPACE_ID" | jq -r '.result.panes[].pane_id' |
  grep -vx "$HERDR_PANE_ID" | while read -r p; do herdr pane close "$p" >/dev/null && echo "closed $p"; done
