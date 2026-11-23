#!/usr/bin/env bash
# Fails when a commit in BASE..HEAD carries no Signed-off-by line (the Developer
# Certificate of Origin, see CONTRIBUTING.md). Merge commits are not checked.
set -euo pipefail
base=$1 head=$2
missing=0
# Listed first, so that a range git cannot read stops the script here.
commits=$(git rev-list --no-merges "$base..$head")
for c in $commits; do
  if ! git show -s --format='%(trailers:key=Signed-off-by,valueonly)' "$c" | grep -qE '^.+ <[^<> ]+@[^<> ]+>$'; then
    echo "No Signed-off-by line: $(git show -s --format='%h %s' "$c")"
    missing=1
  fi
done
if [ "$missing" = 1 ]; then
  echo "Sign off each commit with 'git commit -s'. To fix a branch: git rebase --signoff $base"
  exit 1
fi
echo "Every commit is signed off."
