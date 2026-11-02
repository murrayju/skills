#!/usr/bin/env bash
# Usage: start-ticket.sh <TICKET> <BASE_BRANCH> [EXTRA_PROMPT]
# Make the ticket branch from BASE_BRANCH, open a herdr pane, start a pi
# implementer in it and send the ticket. The branch name comes from the
# "Suggested branch:" line of $STACK_WORK/<TICKET>.md.
source "$(dirname "$0")/common.sh"
set -uo pipefail
TICKET="$1"; BASE="$2"; EXTRA="${3:-}"
BRANCH=$(grep -m1 '^Suggested branch:' "$STACK_WORK/$TICKET.md" | awk '{print $3}')
[ -n "$BRANCH" ] || { echo "no 'Suggested branch:' line in $TICKET.md"; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "tree is dirty"; exit 1; }
git checkout -q "$BASE" && git checkout -q -b "$BRANCH" || exit 1
PANE=$(herdr pane split --pane "$HERDR_PANE_ID" --direction right --cwd "$REPO" --no-focus | jq -r .result.pane.pane_id)
echo "$PANE" > "$STACK_WORK/$TICKET-pane"
S=$(herdr agent start "impl-${TICKET,,}" --kind pi --pane "$PANE" --timeout 120000 -- --model "$IMPLEMENTER_MODEL" --thinking "$THINKING" | jq -r '.result.agent.agent_status // .error.code')
echo "start: $S"
sleep 3
# A pane that shows "Model ... not found" has no agent. Check it.
if herdr pane read "$PANE" --source visible | grep -q 'not found'; then
  echo "pi did not start in $PANE (model not found?). See: herdr pane read $PANE --source visible"; exit 1
fi
PROMPT="Read $STACK_WORK/BRIEF.md first and follow it exactly. Your ticket: $STACK_WORK/$TICKET.md ($TICKET). You are on branch $BRANCH, created from $BASE (see git log --oneline for earlier stacked work). Your PR will target $BASE. $EXTRA As your very last action, touch $STACK_WORK/$TICKET-done."
"$SKILL_SCRIPTS/prompt.sh" "$PANE" "$PROMPT" || exit 1
echo "branch=$BRANCH pane=$PANE"
