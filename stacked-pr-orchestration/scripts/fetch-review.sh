#!/usr/bin/env bash
# Usage: fetch-review.sh <TICKET> [PR]
# Save the automated Claude review: the top-level comment to
# <TICKET>-claude-review.md and the inline comments (with ids) to
# <TICKET>-claude-inline.md. Try again on the short GitHub 404 errors.
source "$(dirname "$0")/common.sh"
T="$1"; PR="${2:-$(read_file "$STACK_WORK/$T-pr-number")}"
for _ in 1 2 3 4 5; do
  gh api "repos/$GH_REPO/issues/$PR/comments" --jq ".[] | select(.user.login==\"$CLAUDE_BOT\") | .body" \
      > "$STACK_WORK/$T-claude-review.md" 2>/dev/null \
    && gh api "repos/$GH_REPO/pulls/$PR/comments" \
      --jq '.[] | "### inline id=\(.id) \(.path):\(.line // .original_line)\n\(.body)\n"' \
      > "$STACK_WORK/$T-claude-inline.md" 2>/dev/null \
    && break
  sleep 10
done
wc -c "$STACK_WORK/$T"-claude-*.md
