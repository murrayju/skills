#!/usr/bin/env bash
# Usage: wait-done.sh <TICKET> [SIGNAL] [MAX_MINUTES]
# Wait for $STACK_WORK/<TICKET>-<SIGNAL> (default SIGNAL: done) and then for
# the agent to stop working. Print progress every 5 minutes.
# The signal file can come before the last writes and commits, and herdr can
# show "working" for a long time after the agent stopped. Thus check both, and
# do not trust only one of them.
source "$(dirname "$0")/common.sh"
TICKET="$1"; SIGNAL="${2:-done}"; MAX="${3:-55}"
PANE=$(read_file "$STACK_WORK/$TICKET-pane") || exit 1
DONE="$STACK_WORK/$TICKET-$SIGNAL"
start=$(date +%s); stable=0; last=0
while [ $(( $(date +%s) - start )) -lt $(( MAX * 60 )) ]; do
  S=$(herdr agent get "$PANE" 2>/dev/null | jq -r '.result.agent.agent_status // "gone"')
  if [ -f "$DONE" ]; then
    if [ "$S" != working ]; then stable=$((stable + 1)); else stable=0; fi
    # Accept a stuck "working" status 3 minutes after the signal.
    if [ "$stable" -ge 3 ] || [ $(( $(date +%s) - $(stat -c %Y "$DONE") )) -gt 180 ]; then
      sleep 10; echo "settled: status=$S"; git log --oneline -5; git status --short | head; exit 0
    fi
  fi
  if [ $(( $(date +%s) - last )) -ge 300 ]; then
    last=$(date +%s)
    echo "$(date +%T) status=$S changed=$(git status --short | wc -l) head=$(git log --oneline -1)"
  fi
  sleep 10
done
echo "not done after $MAX minutes (call again to keep waiting)"; exit 3
