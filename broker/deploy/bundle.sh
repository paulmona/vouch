#!/usr/bin/env bash
# Builds the broker release bundle: deploy/bundle.sh <outdir>
# credbroker-<version>.tar.gz holds the wheel, requirements.txt with a hash for
# every dependency, deploy, the example config and secrets files, LICENSE,
# NOTICE and VERSION/COMMIT, so the target machine installs it with python3 and pip alone.
#
# The files come from the commit that is checked out (git archive HEAD), not from
# the directory: a secrets.env an installer keeps under deploy/ is not in git and
# must not end up in a bundle. A change that is not committed is not in the
# bundle either.
set -euo pipefail
broker=$(cd "$(dirname "$0")/.." && pwd)
root=$(git -C "$broker" rev-parse --show-toplevel)
out=$(mkdir -p "$1" && cd "$1" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/tree"
git -C "$root" archive HEAD broker LICENSE NOTICE | tar -x -C "$work/tree"
src=$work/tree/broker
v=$(python3 -c 'import sys, tomllib; print(tomllib.load(open(sys.argv[1], "rb"))["project"]["version"])' "$src/pyproject.toml")
name=credbroker-$v
mkdir "$work/$name"
uv build -q --project "$src" --wheel -o "$work/$name"
# uv build leaves a .gitignore in its output directory.
rm -f "$work/$name/.gitignore"
(cd "$work/$name" && uv export -q --project "$src" --frozen --no-dev --no-emit-project --no-header -o requirements.txt)
cp -r "$src/deploy" "$src/config.example.toml" "$src/secrets.env.example" "$src/README.md" \
  "$work/tree/LICENSE" "$work/tree/NOTICE" "$work/$name/"
echo "$v" > "$work/$name/VERSION"
git -C "$root" rev-parse HEAD > "$work/$name/COMMIT"
mtime=$(git -C "$root" log -1 --format=%cI)
tar -C "$work" --sort=name --owner=0 --group=0 --numeric-owner --mtime="$mtime" -czf "$out/$name.tar.gz" "$name"
(cd "$out" && sha256sum "$name.tar.gz" > "$name.tar.gz.sha256")
echo "$out/$name.tar.gz"
