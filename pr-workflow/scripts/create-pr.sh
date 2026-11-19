#!/usr/bin/env bash
# Usage: create-pr.sh <TICKET> <BASE_BRANCH>
# Push (with checks), then open the PR with the title and body files of the
# implementer. Give --head: gh cannot find the branch if the push is not done.
source "$(dirname "$0")/common.sh"
TICKET="$1"; BASE="$2"
TITLE=$(read_file "$PR_WORK/$TICKET-pr-title.txt") || exit 1
read_file "$PR_WORK/$TICKET-pr.md" >/dev/null || exit 1
if grep -q '—' "$PR_WORK/$TICKET-pr.md" "$PR_WORK/$TICKET-pr-title.txt"; then
  echo "the PR text has em dashes; fix them first"; exit 1
fi
"$SKILL_SCRIPTS/push-check.sh" || exit 1
URL=$(gh pr create --base "$BASE" --head "$(git branch --show-current)" --title "$TITLE" \
  --body-file "$PR_WORK/$TICKET-pr.md" 2>&1 | tail -1)
echo "$URL"
[[ "$URL" =~ /pull/([0-9]+)$ ]] && echo "${BASH_REMATCH[1]}" > "$PR_WORK/$TICKET-pr-number"
