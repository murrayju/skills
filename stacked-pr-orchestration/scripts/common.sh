# Shared setup for the stacked-pr-orchestration scripts. Source this file.
# It loads the config of the current run from $STACK_WORK/config.env.
if [ -z "${STACK_WORK:-}" ]; then
  echo "STACK_WORK is not set. Run init.sh, then export STACK_WORK." >&2
  exit 2
fi
# shellcheck disable=SC1091
source "$STACK_WORK/config.env"
SKILL_SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The tools of the pi-advisor extension. Give "--exclude-tools $ADVISOR_TOOLS"
# to pi to run it without the Advisor. All Advisor paths need ask_advisor.
ADVISOR_TOOLS="ask_advisor,record_advisor_outcome"
cd "$REPO" || exit 2

# Start pi in a pane, with the content of PROMPT_FILE as its first message.
# This is the method of the review skill: a runner script that "exec"s pi with
# a positional message. The first prompt cannot get lost (an "agent prompt"
# right after a start can), and the pane closes when pi exits.
# Give more pi arguments after PROMPT_FILE, for example
# --exclude-tools "$ADVISOR_TOOLS" to start pi without the Advisor.
# Usage: launch_pi <PANE> <MODEL> <PROMPT_FILE> [PI_ARG...]
launch_pi() {
  local pane="$1" model="$2" prompt_file="$3"
  shift 3
  local runner="${prompt_file%.*}-run.sh" extra_args=""
  # Quote each argument for the runner script.
  [ "$#" -gt 0 ] && extra_args=$(printf ' %q' "$@")
  cat > "$runner" <<RUN
#!/usr/bin/env bash
exec pi --model "$model" --thinking "$THINKING"$extra_args "\$(cat '$prompt_file')"
RUN
  chmod +x "$runner"
  # Keep the command short. The runner reads the long prompt from its file.
  herdr pane run "$pane" "exec $runner" >/dev/null
}

# Return 0 if herdr says that the pane does not exist. Other herdr errors can
# be short failures, so they do not count.
pane_gone() {
  herdr pane get "$1" 2>&1 >/dev/null | grep -q pane_not_found
}

# Wait until herdr sees pi working in the pane. Fail if the pane closes, if pi
# shows an error and stops (for example "model_not_found": pi does not exit,
# it stays idle with the error on the screen), or after 120 s.
# Usage: wait_working <PANE>
wait_working() {
  local pane="$1" s
  for _ in $(seq 1 60); do
    if pane_gone "$pane"; then echo "pane $pane closed: pi exited at start"; return 1; fi
    s=$(herdr pane get "$pane" 2>/dev/null | jq -r '.result.pane.agent_status // empty')
    [ "$s" = working ] && return 0
    if [ "$s" = idle ] && herdr pane read "$pane" --source visible | grep -q 'Error:'; then
      echo "pi in $pane stopped with an error:"
      herdr pane read "$pane" --source visible | grep -A2 'Error:' | head -5
      return 1
    fi
    sleep 2
  done
  echo "pi in $pane is not working after 120 s. See: herdr pane read $pane --source visible"
  return 1
}

# Read a file again a few times before it fails. Reads right after a subagent
# writes a file can fail for a short time.
read_file() {
  local file="$1"
  for _ in 1 2 3 4 5; do
    [ -f "$file" ] && { cat "$file"; return 0; }
    sleep 2
  done
  echo "missing: $file" >&2
  return 1
}
