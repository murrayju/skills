#!/usr/bin/env bash
# Usage: ci-failures.sh <PR> | ci-failures.sh job:<JOB_NUMBER>
# For each failed CircleCI job of the PR: print the failed steps, the failed
# tests and the end of the failed step output. Uses the CircleCI API, because
# the CircleCI MCP log tool often finds no logs or the wrong job.
# The token comes from $CIRCLECI_TOKEN or the pi MCP config.
source "$(dirname "$0")/common.sh"
PR="$1"
T="${CIRCLECI_TOKEN:-$(jq -r '.. | objects | select(has("CIRCLECI_TOKEN")) | .CIRCLECI_TOKEN' ~/.pi/agent/mcp.json 2>/dev/null | head -1)}"
[ -n "$T" ] || { echo "no CircleCI token"; exit 1; }
SLUG="github/$GH_REPO"
if [[ "$PR" == job:* ]]; then
  echo "${PR#job:}"
else
  gh pr checks "$PR" 2>/dev/null | awk -F'\t' '$2=="fail" {print $4}' | grep -o 'circleci.com/gh/[^/]*/[^/]*/[0-9]*$' | grep -o '[0-9]*$'
fi |
while read -r JOB; do
  INFO=$(curl -s -H "Circle-Token: $T" "https://circleci.com/api/v1.1/project/$SLUG/$JOB")
  echo "===== job $JOB: $(echo "$INFO" | jq -r '.workflows.job_name // .build_parameters.CIRCLE_JOB // "?"') (workflow $(echo "$INFO" | jq -r '.workflows.workflow_id'))"
  echo "$INFO" | jq -r '.steps[] | select(.actions[0].status != "success") | "step: \(.name) :: \(.actions[0].status)"'
  curl -s -H "Circle-Token: $T" "https://circleci.com/api/v2/project/gh/$GH_REPO/$JOB/tests" |
    jq -r '.items[]? | select(.result!="success" and .result!="skipped") | "test: \(.file // .classname) :: \(.name) :: \(.message|tostring|.[0:300])"' | head -20
  URL=$(echo "$INFO" | jq -r '[.steps[] | select(.actions[0].status=="failed")][0].actions[0].output_url // empty')
  [ -n "$URL" ] && curl -s "$URL" | jq -r '.[].message' | sed 's/\x1b\[[0-9;]*m//g' | tail -40
done
echo "Rerun failed jobs: the CircleCI MCP rerun_workflow tool with {workflowId, fromFailed: true}."
