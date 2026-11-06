#!/usr/bin/env bash
# Usage: [IMPLEMENTER_MODEL=..] [ADVISOR_MODEL=..] [REVIEWER_MODEL_1=..] [REVIEWER_MODEL_2=..] \
#          init.sh <RUN_ID> <REPO_PATH> [GH_REPO]
# Make the work directory of a run and its config. Print the export line.
# Ask the user for the models first, and pass the answers as environment
# variables. The defaults below apply only to a model the user did not name.
# Keep the work directory out of /tmp: state files there were lost during
# earlier runs.
set -euo pipefail
RUN_ID="$1"; REPO_PATH="$(cd "$2" && pwd)"
GH_REPO="${3:-$(cd "$REPO_PATH" && gh repo view --json nameWithOwner -q .nameWithOwner)}"
WORK="$HOME/.cache/stacked-pr/$RUN_ID"
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$WORK/review"
if [ ! -f "$WORK/config.env" ]; then
  cat > "$WORK/config.env" <<CONF
# Config of the stacked PR run $RUN_ID.
REPO="$REPO_PATH"
GH_REPO="$GH_REPO"
# pi model ids, chosen by the user and resolved with resolve-model.sh (concentrate
# first, openrouter second, other providers last).
# The implementer runs with the pi-advisor extension. The reviewers run
# without it (start-review.sh excludes the Advisor tools).
IMPLEMENTER_MODEL="${IMPLEMENTER_MODEL:-concentrate/deepseek-v4-1-flash-1017}"
IMPLEMENTER_FALLBACK_MODEL="${IMPLEMENTER_FALLBACK_MODEL:-openrouter/deepseek/deepseek-v4.1-flash-1017}"
# The Advisor model is global ("advisor" in ~/.pi/agent/advisor.json).
# preflight.sh checks that it equals this value. It does not change it.
ADVISOR_MODEL="${ADVISOR_MODEL:-concentrate/claude-opus-5-5}"
# Review round 1 runs before the PR opens. Round 2 runs after the round 1
# fixes, next to the automated PR review. Use two different model families.
REVIEWER_MODEL_1="${REVIEWER_MODEL_1:-concentrate/gpt-6.1-sol}"
REVIEWER_MODEL_2="${REVIEWER_MODEL_2:-concentrate/claude-opus-5-5}"
THINKING="high"
# The GitHub check of the automated Claude review, and the bot login.
CLAUDE_REVIEW_CHECK="claude-review"
CLAUDE_BOT="claude[bot]"
CONF
else
  echo "config exists, not changed: $WORK/config.env (edit it to change models)" >&2
fi
# The panes of the subagents do not have STACK_WORK, so write the real path.
[ -f "$WORK/BRIEF.md" ] || sed "s#\$STACK_WORK#$WORK#g" "$SKILL_DIR/templates/BRIEF.md" > "$WORK/BRIEF.md"
touch "$WORK/ORDER.txt"
echo "export STACK_WORK=$WORK"
