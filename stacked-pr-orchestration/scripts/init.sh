#!/usr/bin/env bash
# Usage: init.sh <RUN_ID> <REPO_PATH> [GH_REPO]
# Make the work directory of a run and its config. Print the export line.
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
# pi model ids. Check them with: pi --list-models <pattern>
# The implementer runs with the pi-advisor extension. The reviewer runs
# without it (start-review.sh excludes the Advisor tools).
IMPLEMENTER_MODEL="concentrate/deepseek-v4-1-flash-1017"
IMPLEMENTER_FALLBACK_MODEL="openrouter/deepseek/deepseek-v4.1-flash-1017"
# The Advisor model is global ("advisor" in ~/.pi/agent/advisor.json).
# preflight.sh checks that it equals this value. It does not change it.
ADVISOR_MODEL="concentrate/claude-opus-5-5"
REVIEWER_MODEL="openai-codex/gpt-6.1-sol"
THINKING="high"
# The GitHub check of the automated Claude review, and the bot login.
CLAUDE_REVIEW_CHECK="claude-review"
CLAUDE_BOT="claude[bot]"
CONF
fi
# The panes of the subagents do not have STACK_WORK, so write the real path.
[ -f "$WORK/BRIEF.md" ] || sed "s#\$STACK_WORK#$WORK#g" "$SKILL_DIR/templates/BRIEF.md" > "$WORK/BRIEF.md"
touch "$WORK/ORDER.txt"
echo "export STACK_WORK=$WORK"
