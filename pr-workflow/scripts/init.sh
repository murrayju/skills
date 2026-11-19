#!/usr/bin/env bash
# Usage: [IMPLEMENTER_MODEL=..] [REVIEWER_MODELS="<id> <id> .."] \
#          init.sh <RUN_ID> <REPO_PATH> [GH_REPO]
# Make the work directory of a run and its config. Print the export line.
# Do not ask the user for the models. The defaults: the implementer uses the
# model of the current pi session, and the reviewers are the newest carbon,
# astra and fable models. Give other values only if the user named them.
# The Advisor of the implementer is the global pi-advisor config. This script
# does not set it.
# Keep the work directory out of /tmp: state files there were lost during
# earlier runs.
set -euo pipefail
RUN_ID="$1"; REPO_PATH="$(cd "$2" && pwd)"
GH_REPO="${3:-$(cd "$REPO_PATH" && gh repo view --json nameWithOwner -q .nameWithOwner)}"
WORK="$HOME/.cache/pr-workflow/$RUN_ID"
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$WORK/review"
if [ ! -f "$WORK/config.env" ]; then
  if [ -z "${IMPLEMENTER_MODEL:-}" ]; then
    [ -n "${PI_PROVIDER:-}" ] && [ -n "${PI_MODEL:-}" ] || { echo "PI_PROVIDER/PI_MODEL not set: give IMPLEMENTER_MODEL" >&2; exit 1; }
    IMPLEMENTER_MODEL="$PI_PROVIDER/$PI_MODEL"
  fi
  if [ -z "${REVIEWER_MODELS:-}" ]; then
    for name in carbon astra fable; do
      id=$("$SKILL_DIR/scripts/resolve-model.sh" "$name" 1 2>/dev/null)
      [ -n "$id" ] || { echo "no model matches '$name'" >&2; exit 1; }
      REVIEWER_MODELS="${REVIEWER_MODELS:+$REVIEWER_MODELS }$id"
    done
  fi
  cat > "$WORK/config.env" <<CONF
# Config of the pr-workflow run $RUN_ID.
REPO="$REPO_PATH"
GH_REPO="$GH_REPO"
# Full pi model ids (resolve names with resolve-model.sh).
# The implementer runs with the global pi-advisor config. The reviewers run
# without the Advisor (start-review.sh excludes the Advisor tools).
IMPLEMENTER_MODEL="$IMPLEMENTER_MODEL"
# The reviewers, in order. Review round N uses the reviewer at position
# (N-1) modulo the count, so each pass runs every reviewer once, in order.
REVIEWER_MODELS="$REVIEWER_MODELS"
THINKING="high"
# The GitHub check of the automated PR review. Set it to "" if the
# repository has no automated review.
CLAUDE_REVIEW_CHECK="claude-review"
CONF
else
  echo "config exists, not changed: $WORK/config.env (edit it to change models)" >&2
fi
# The panes of the subagents do not have PR_WORK, so write the real path.
[ -f "$WORK/BRIEF.md" ] || sed "s#\$PR_WORK#$WORK#g" "$SKILL_DIR/templates/BRIEF.md" > "$WORK/BRIEF.md"
touch "$WORK/ORDER.txt"
grep -E '^(IMPLEMENTER_MODEL|REVIEWER_MODELS)=' "$WORK/config.env" >&2
echo "export PR_WORK=$WORK"
