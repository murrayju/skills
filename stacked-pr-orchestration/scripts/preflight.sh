#!/usr/bin/env bash
# Usage: preflight.sh
# Check the things that stopped earlier runs: herdr, commit signing, model
# auth, gh auth and a clean tree. Run it before each ticket.
source "$(dirname "$0")/common.sh"
ok=1
[ "${HERDR_ENV:-}" = 1 ] && echo "herdr: ok ($HERDR_PANE_ID)" || { echo "herdr: NOT in a herdr pane"; ok=0; }
if [ "$(git config --get commit.gpgsign)" = true ]; then
  echo test | gpg --clearsign >/dev/null 2>&1 && echo "gpg: ok" || { echo "gpg: SIGNING FAILS (ask the user to unlock gpg)"; ok=0; }
fi
for m in "$IMPLEMENTER_MODEL" "$REVIEWER_MODEL"; do
  r=$(pi auth check --provider "${m%%/*}" --model "${m#*/}" 2>&1 | tail -1)
  listed=$(pi --list-models "${m#*/}" 2>/dev/null | awk -v p="${m%%/*}" -v id="${m#*/}" '$1==p && $2==id' | wc -l)
  if [ "$r" = ready ] && [ "$listed" -ge 1 ]; then echo "model $m: ok"; else echo "model $m: NOT READY ($r, listed=$listed)"; ok=0; fi
done
gh auth status >/dev/null 2>&1 && echo "gh: ok" || { echo "gh: not logged in"; ok=0; }
[ -z "$(git status --porcelain)" ] && echo "tree: clean ($(git branch --show-current))" || { echo "tree: DIRTY"; git status --short | head; ok=0; }
[ "$ok" = 1 ] || exit 1
