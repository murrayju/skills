# Shared setup for the stacked-pr-orchestration scripts. Source this file.
# It loads the config of the current run from $STACK_WORK/config.env.
if [ -z "${STACK_WORK:-}" ]; then
  echo "STACK_WORK is not set. Run init.sh, then export STACK_WORK." >&2
  exit 2
fi
# shellcheck disable=SC1091
source "$STACK_WORK/config.env"
SKILL_SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO" || exit 2

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
