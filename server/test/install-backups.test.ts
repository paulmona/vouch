// deploy/install.sh runs as root, and the database it backs up and restores sits in a
// directory the service's user owns. These run its functions as root against a scratch
// directory, with `nobody` standing in for a service account that has been taken over.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { test } from "node:test";

const INSTALL = new URL("../deploy/install.sh", import.meta.url).pathname;
const sudo = spawnSync("sudo", ["-n", "true"]).status === 0;
const skip = sudo ? false : "needs passwordless sudo";

const SETUP = `
set -euo pipefail
d=$(mktemp -d); chmod 755 "$d"; trap 'rm -rf "$d"' EXIT
source "$INSTALL"
instance test
SVC_USER=nobody STATE=$d/state DB=$d/state/vouch.db BACKUPS=$d/backups ROOT=$d/opt
install -d -m 0700 -o nobody -g "$(id -gn nobody)" "$STATE"
install -d -m 0700 "$BACKUPS"
mkdir -p "$ROOT/1.0.0/migrations"; touch "$ROOT/1.0.0/migrations/0001_first.sql"
svc() { runuser -u nobody -- "$@"; }
svc mkdir "$STATE/backups"     # where copies used to go: the service's user can always make it
database() {                   # a database that has run the migrations named
  svc node -e '
    const db = new (require("node:sqlite").DatabaseSync)(process.argv[1]);
    db.exec("CREATE TABLE migrations (name TEXT)");
    for (const n of process.argv.slice(2)) db.prepare("INSERT INTO migrations VALUES (?)").run(n);
  ' "$DB" "$@"
}
`;

function root(body: string) {
  const r = spawnSync("sudo", ["-n", "env", `PATH=${process.env.PATH}`, `INSTALL=${INSTALL}`, "bash", "-c", SETUP + body],
    { encoding: "utf8", timeout: 60_000 });
  return { code: r.status, out: r.stdout, all: r.stdout + r.stderr };
}

test("the backup directory belongs to root, outside the service's own directory", { skip }, () => {
  const r = root(`
    rmdir "$BACKUPS"
    svc sh -c 'echo database > "$1"' sh "$DB"
    snapshot 1.0.0 >/dev/null
    stat -c '%U %a' "$BACKUPS"
    instance prod; echo "$BACKUPS"; case $BACKUPS in "$STATE"/*) echo inside ;; esac
  `);
  assert.equal(r.code, 0, r.all);
  assert.deepEqual(r.out.trim().split("\n").slice(-2), ["root 700", "/var/backups/vouch"], r.all);
});

test("a backup is not written through a link the service's user planted", { skip }, () => {
  const r = root(`
    echo untouched > "$d/victim"
    svc sh -c 'echo database > "$1"' sh "$DB"
    for s in 0 1 2 3 4 5; do svc ln -s "$d/victim" "$STATE/backups/1.0.0-$(date -d "+$s sec" +%Y%m%dT%H%M%S).db"; done
    snapshot 1.0.0 >/dev/null
    echo "victim=$(cat "$d/victim")"
    echo "copy=$(cat "$BACKUPS"/1.0.0-*.db) owner=$(stat -c %U "$BACKUPS"/1.0.0-*.db)"
  `);
  assert.equal(r.code, 0, r.all);
  assert.match(r.out, /^victim=untouched$/m, "root wrote the database over another file");
  assert.match(r.out, /^copy=database owner=root$/m);
});

test("a backup does not copy a file only root can read", { skip }, () => {
  const r = root(`
    (umask 077; echo ROOT-ONLY > "$d/secret")
    svc ln -s "$d/secret" "$DB"
    (snapshot 1.0.0) >/dev/null 2>&1 && echo "snapshot succeeded"
    grep -rl ROOT-ONLY "$BACKUPS" "$STATE/backups" && echo copied
    exit 0
  `);
  assert.equal(r.code, 0, r.all);
  assert.doesNotMatch(r.out, /copied|snapshot succeeded/, r.all);
});

test("a restore uses root's copy, not one the service's user left, and hands the file back", { skip }, () => {
  const r = root(`
    database 0001_first.sql 0002_later.sql
    echo GOOD > "$BACKUPS/1.0.0-20260101T000000.db"
    svc sh -c 'echo EVIL > "$1"' sh "$STATE/backups/1.0.0-29990101T000000.db"
    restore_for 1.0.0 >/dev/null
    echo "db=$(cat "$DB") $(stat -c '%U %a' "$DB")"
  `);
  assert.equal(r.code, 0, r.all);
  assert.match(r.out, /^db=GOOD nobody 600$/m, r.all);
});

test("a rollback stops when the database cannot be read, instead of starting old code on it", { skip }, () => {
  const r = root(`
    svc sh -c 'echo "this is not a database" > "$1"' sh "$DB"
    echo GOOD > "$BACKUPS/1.0.0-20260101T000000.db"
    restore_for 1.0.0
    echo "went on"
  `);
  assert.notEqual(r.code, 0, r.all);
  assert.doesNotMatch(r.out, /went on/);
  assert.match(r.all, /could not read which migrations/);
});

test("a database the release already understands is left alone", { skip }, () => {
  const r = root(`
    database 0001_first.sql
    before=$(sha256sum < "$DB")
    echo GOOD > "$BACKUPS/1.0.0-20260101T000000.db"
    restore_for 1.0.0
    [ "$before" = "$(sha256sum < "$DB")" ] && echo unchanged
  `);
  assert.equal(r.code, 0, r.all);
  assert.match(r.out, /^unchanged$/m);
});
