#!/usr/bin/env bash
# Usage: fetch-feedback.sh <TICKET> [PR]
# Save all PR feedback to $PR_WORK/<TICKET>-feedback.md: the PR comments,
# the review bodies and the inline comments (with their ids, for
# post-replies.py). This includes the automated review and the comments of
# people. It leaves out the comments of the current gh user (our replies).
# Try again on the short GitHub 404 errors.
source "$(dirname "$0")/common.sh"
T="$1"; PR="${2:-$(read_file "$PR_WORK/$T-pr-number")}"
OUT="$PR_WORK/$T-feedback.md"
ME=$(gh api user --jq .login) || exit 1
NOT_ME="select(.user.login != \"$ME\")"
for _ in 1 2 3 4 5; do
  {
    gh api --paginate "repos/$GH_REPO/issues/$PR/comments" \
      --jq ".[] | $NOT_ME | \"## comment by \(.user.login) at \(.created_at)\n\(.body)\n\"" &&
    gh api --paginate "repos/$GH_REPO/pulls/$PR/reviews" \
      --jq ".[] | $NOT_ME | select(.body != \"\") | \"## review by \(.user.login) (\(.state)) at \(.submitted_at)\n\(.body)\n\"" &&
    gh api --paginate "repos/$GH_REPO/pulls/$PR/comments" \
      --jq ".[] | $NOT_ME | \"## inline id=\(.id) by \(.user.login) at \(.created_at) \(.path):\(.line // .original_line)\n\(.body)\n\""
  } > "$OUT" 2>/dev/null && break
  sleep 10
done
echo "$(grep -c '^## comment by' "$OUT") comments, $(grep -c '^## review by' "$OUT") reviews, $(grep -c '^## inline id=' "$OUT") inline comments: $OUT"
