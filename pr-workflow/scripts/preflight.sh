#!/usr/bin/env bash
# Usage: preflight.sh
# Check the things that stopped earlier runs: herdr, commit signing, model
# auth, gh auth and a clean tree. Run it before each ticket.
# A "WARN" line does not stop the run. Tell the user about it in the summary.
source "$(dirname "$0")/common.sh"
ok=1
[ "${HERDR_ENV:-}" = 1 ] && echo "herdr: ok ($HERDR_PANE_ID)" || { echo "herdr: NOT in a herdr pane"; ok=0; }
if [ "$(git config --get commit.gpgsign)" = true ]; then
  echo test | gpg --clearsign >/dev/null 2>&1 && echo "gpg: ok" || { echo "gpg: SIGNING FAILS (ask the user to unlock gpg)"; ok=0; }
fi
[ -n "${IMPLEMENTER_MODEL:-}" ] || { echo "config: IMPLEMENTER_MODEL is not set in $PR_WORK/config.env"; ok=0; }
[ -n "${SCRIBE_MODEL:-}" ] || { echo "config: SCRIBE_MODEL is not set in $PR_WORK/config.env"; ok=0; }
[ -n "${REVIEWER_MODELS:-}" ] || { echo "config: REVIEWER_MODELS is not set in $PR_WORK/config.env"; ok=0; }
checked_models=" "
for m in ${IMPLEMENTER_MODEL:-} ${SCRIBE_MODEL:-} ${REVIEWER_MODELS:-}; do
  case "$checked_models" in *" $m "*) continue ;; esac
  checked_models="$checked_models$m "
  r=$(pi auth check --provider "${m%%/*}" --model "${m#*/}" 2>&1 | tail -1)
  listed=$(pi --list-models "${m#*/}" 2>/dev/null | awk -v p="${m%%/*}" -v id="${m#*/}" '$1==p && $2==id' | wc -l)
  if [ "$r" = ready ] && [ "$listed" -ge 1 ]; then echo "model $m: ok"; else echo "model $m: NOT READY ($r, listed=$listed)"; ok=0; fi
done
for m in ${REVIEWER_MODELS:-}; do
  [ "$m" != "${IMPLEMENTER_MODEL:-}" ] || echo "WARN: reviewer $m is also the implementer model"
done
# The implementer uses the global Advisor config. Only check it: it is the
# user's setting. Do not use ".x // true": jq treats false as missing there.
A="$HOME/.pi/agent/advisor.json"
adv_tools=$(jq -r 'if has("advisorToolsEnabled") then .advisorToolsEnabled else true end' "$A" 2>/dev/null)
adv_same_off=$(jq -r 'if has("advisorDisableSameModel") then .advisorDisableSameModel else true end' "$A" 2>/dev/null)
adv_model=$(jq -r '.advisor // empty' "$A" 2>/dev/null)
if [ "$adv_tools" != true ] || [ -z "$adv_model" ]; then
  echo "WARN: advisor: not enabled in $A, so the implementer has no Advisor"
elif [ "$adv_model" = "${IMPLEMENTER_MODEL:-}" ] && [ "$adv_same_off" = true ]; then
  echo "WARN: advisor: $adv_model is the implementer model, so pi-advisor skips every call"
else
  echo "advisor: ok ($adv_model)"
fi
gh auth status >/dev/null 2>&1 && echo "gh: ok" || { echo "gh: not logged in"; ok=0; }
[ -z "$(git status --porcelain)" ] && echo "tree: clean ($(git branch --show-current))" || { echo "tree: DIRTY"; git status --short | head; ok=0; }
[ "$ok" = 1 ] || exit 1
