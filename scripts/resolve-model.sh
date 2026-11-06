#!/usr/bin/env bash
# Resolve the name of a model to full provider/model ids, using the live
# catalog from "pi --list-models". Prints the best matches, best first.
# Usage: resolve-model.sh <what the user typed> [count]
#
# Order: exact id, then provider (concentrate, openrouter, others), then the
# newest generation, then the shortest name. The skills use this file through a
# symlink from their own scripts/ folder. Do not copy it.
#
# Exit 0 with no output: nothing matches. Non-zero: the catalog could not be read.
set -euo pipefail
want=$(printf '%s' "${1:?usage: resolve-model.sh <term> [count]}" | tr '[:upper:]' '[:lower:]' | tr '._' '--')
count=${2:-3}

pi --list-models | awk -v want="$want" -v count="$count" '
function number_in(token) {   # v4 -> 4, qwen3 -> 3, flash -> ""
  if (token ~ /^[0-9]+$/) return token
  if (token ~ /^[a-z]+[0-9]+$/) { sub(/^[a-z]+/, "", token); return token }
  return ""
}
function provider_rank(name) { return name == "concentrate" ? 0 : name == "openrouter" ? 1 : 2 }
NR == 1 { words = split(want, word, " "); next }   # every word must match
$2 ~ /^~/ || $2 ~ /:(batch|free)$/ { next }        # skip aliases, batch and free tiers
{
  id = tolower($1 "/" $2); gsub(/[._]/, "-", id)
  for (i = 1; i <= words; i++) if (!index(id, word[i])) next
  model = tolower($2); gsub(/[._]/, "-", model)
  n = split(model, token, "-")                    # the first run of numbers is
  version = ""                                    # the version: 6.1, 5.5, 3.8
  for (i = 1; i <= n; i++) {
    d = number_in(token[i])
    if (d == "") { if (version != "") break; continue }
    version = version sprintf(".%03d", d)
  }
  printf "%d\t%d\t%s\t%d\t%s\n", (id == want ? 0 : 1), provider_rank($1), version, length($2), $1 "/" $2
}' | sort -t$'\t' -k1,1n -k2,2n -k3,3r -k4,4n -k5,5 | cut -f5 \
  | awk -v count="$count" 'NR <= count'
