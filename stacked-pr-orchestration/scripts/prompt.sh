#!/usr/bin/env bash
# Usage: prompt.sh <PANE> <TEXT or @FILE>
# Send a prompt to the agent in a pane. Try again until the agent works.
# herdr can say agent_not_found or agent_prompt_stalled for a short time
# after a start. A failed prompt is not delivered.
PANE="$1"; TEXT="$2"
[ "${TEXT:0:1}" = "@" ] && TEXT="$(cat "${TEXT:1}")"
for t in 1 2 3 4 5; do
  R=$(herdr agent prompt "$PANE" "$TEXT" --wait --until working --timeout 30000 2>&1 | jq -r '.result.agent.agent_status // .error.code' 2>/dev/null)
  echo "prompt attempt $t: $R"
  [ "$R" = working ] && exit 0
  sleep 15
done
exit 1
