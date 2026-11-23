#!/usr/bin/env bash
# Builds the server release bundle: deploy/bundle.sh <outdir>
# vouch-server-<version>.tar.gz holds src, migrations, deploy, production
# node_modules, LICENSE, NOTICE and VERSION/COMMIT, so the server installs it without npm.
#
# The files come from the commit that is checked out (git archive HEAD), not from
# the directory: a secrets.env or firebase.json an installer keeps under deploy/
# is not in git and must not end up in a bundle. A change that is not committed
# is not in the bundle either.
set -euo pipefail
server=$(cd "$(dirname "$0")/.." && pwd)
root=$(git -C "$server" rev-parse --show-toplevel)
out=$(mkdir -p "$1" && cd "$1" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/tree"
git -C "$root" archive HEAD server/src server/migrations server/deploy server/package.json server/package-lock.json \
  server/config.example.toml server/README.md LICENSE NOTICE | tar -x -C "$work/tree"
v=$(node -p 'require(process.argv[1]).version' "$work/tree/server/package.json")
name=vouch-server-$v
mv "$work/tree/server" "$work/$name"
mv "$work/tree/LICENSE" "$work/tree/NOTICE" "$work/$name/"
(cd "$work/$name" && npm ci --omit=dev --ignore-scripts --no-audit --no-fund --silent)
echo "$v" > "$work/$name/VERSION"
git -C "$root" rev-parse HEAD > "$work/$name/COMMIT"
mtime=$(git -C "$root" log -1 --format=%cI)
tar -C "$work" --sort=name --owner=0 --group=0 --numeric-owner --mtime="$mtime" -czf "$out/$name.tar.gz" "$name"
(cd "$out" && sha256sum "$name.tar.gz" > "$name.tar.gz.sha256")
echo "$out/$name.tar.gz"
