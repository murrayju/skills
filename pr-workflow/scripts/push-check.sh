#!/usr/bin/env bash
# Usage: push-check.sh
# Push the current branch. Then make sure that the remote head is HEAD and
# that the tree is clean. Never push a dirty tree: the implementer can still
# be writing.
source "$(dirname "$0")/common.sh"
[ -z "$(git status --porcelain)" ] || { echo "DIRTY TREE"; git status --short | head; exit 1; }
git push -u origin HEAD 2>&1 | tail -1
git fetch -q origin
B=$(git branch --show-current)
if [ "$(git rev-parse HEAD)" = "$(git rev-parse "origin/$B")" ]; then
  echo "PUSHED OK $(git rev-parse --short HEAD)"
else
  echo "PUSH MISMATCH"; exit 1
fi
