#!/usr/bin/env bash
# Usage: wait-pr.sh <PR> [MAX_MINUTES] [--review]
# Wait until no check is pending. Print the checks.
# With --review, also wait for the automated PR review check. That review
# runs only when the PR opens (or on a review request), not after a push, so
# use --review only for the first wait.
source "$(dirname "$0")/common.sh"
PR="$1"; MAX="${2:-90}"; NEED_REVIEW=0
# With no automated review in the repository (CLAUDE_REVIEW_CHECK=""),
# --review does nothing.
[ "${3:-}" = "--review" ] && [ -n "${CLAUDE_REVIEW_CHECK:-}" ] && NEED_REVIEW=1
sleep 45
OUT=""
for _ in $(seq 1 $(( MAX * 2 ))); do
  OUT=$(gh pr checks "$PR" 2>/dev/null)
  PENDING=$(echo "$OUT" | awk -F'\t' '$2=="pending" || $2=="queued" || $2=="in_progress"' | wc -l)
  HAS_REVIEW=$(echo "$OUT" | awk -F'\t' -v c="$CLAUDE_REVIEW_CHECK" '$1==c && $2!="pending"' | wc -l)
  if [ -n "$OUT" ] && [ "$PENDING" -eq 0 ] && { [ "$NEED_REVIEW" -eq 0 ] || [ "$HAS_REVIEW" -ge 1 ]; }; then break; fi
  sleep 30
done
echo "$OUT" | awk -F'\t' '{print $2"\t"$1"\t"$4}'
echo "$OUT" | awk -F'\t' '$2=="fail"' | grep -q . && exit 4 || exit 0
