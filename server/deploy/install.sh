#!/usr/bin/env bash
# Installs a Vouch server release on this machine, or rolls one back. Run it as yourself
# from a checkout; it downloads with gh (which must be able to read this repo's
# releases, e.g. through GH_TOKEN) and uses sudo for the rest.
#
#   deploy/install.sh <test|prod> server-vX.Y.Z   install that release and switch to it
#   deploy/install.sh <test|prod> --bundle FILE   the same from a local bundle (deploy/bundle.sh)
#   deploy/install.sh <test|prod> --rollback      switch back to the previous release
#   deploy/install.sh <test|prod> --status
#   deploy/install.sh test --reset                forget every device and request
#
# Releases live in /opt/vouch/<instance>/<version>, with `current` and
# `previous` symlinks. Before a switch the database is copied to
# /var/backups/vouch (or vouch-test). The new version must answer /healthz with its own version,
# or the previous one is put back. Migrations run when the service starts; a
# rollback across a migration restores the copy taken when that version was
# left, since older code refuses a database with migrations it does not know.
set -euo pipefail

REPO=${VOUCH_REPO:-paulmona/vouch}
KEEP=5
die() { echo "install: $*" >&2; exit 1; }
say() { echo "install: $*"; }

instance() {
  case ${1:-} in
    prod) SVC_USER=vouch UNIT=vouch ETC=/etc/vouch STATE=/var/lib/vouch RUN=/run/vouch ;;
    test) SVC_USER=vouch-test UNIT=vouch-test ETC=/etc/vouch-test STATE=/var/lib/vouch-test RUN=/run/vouch-test ;;
    *) die "the instance is test or prod" ;;
  esac
  INST=$1
  ROOT=/opt/vouch/$1
  DB=$STATE/vouch.db
  # Not under $STATE: the service's user owns that, and root must not write, pick a file
  # to restore, or delete by name in a directory someone else controls.
  BACKUPS=/var/backups/$UNIT
}

# Everything root does to the database file itself runs as the service's user, so a link
# planted in its directory reaches nothing that user could not already reach.
as_svc() { runuser -u "$SVC_USER" -- "$@"; }

version_of() { local l; l=$(readlink "$ROOT/$1" 2>/dev/null) && basename "$l" || true; }

# --- as yourself ---------------------------------------------------------

fetch_and_install() {
  local tag=$1 v
  [[ $tag =~ ^server-v([0-9]+\.[0-9]+\.[0-9]+)$ ]] || die "not a server release tag: $tag"
  v=${BASH_REMATCH[1]}
  # Global, not local: the EXIT trap runs after this function has returned.
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  gh release download "$tag" -R "$REPO" -D "$tmp" -p "vouch-server-$v.tar.gz" -p "vouch-server-$v.tar.gz.sha256"
  (cd "$tmp" && sha256sum --quiet -c "vouch-server-$v.tar.gz.sha256") || die "checksum mismatch for $tag"
  sudo "$0" __activate "$INST" "$v" "$tmp/vouch-server-$v.tar.gz"
}

install_bundle() {
  local file=$1 v
  [[ $(basename "$file") =~ ^vouch-server-([0-9]+\.[0-9]+\.[0-9]+)\.tar\.gz$ ]] || die "not a bundle: $file"
  v=${BASH_REMATCH[1]}
  (cd "$(dirname "$file")" && sha256sum --quiet -c "$(basename "$file").sha256") || die "checksum mismatch for $file"
  sudo "$0" __activate "$INST" "$v" "$(cd "$(dirname "$file")" && pwd)/$(basename "$file")"
}

# --- as root -------------------------------------------------------------

setup_host() {
  id "$SVC_USER" >/dev/null 2>&1 ||
    useradd --system --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin "$SVC_USER"
  install -d -m 0700 -o "$SVC_USER" -g "$SVC_USER" "$STATE"
  install -d -m 0700 -o root -g root "$BACKUPS"
  if [ "$INST" = prod ]; then
    # Membership decides who may connect: add your broker's user to vouch-broker
    # and your texting agent's user to vouch-sms (usermod -aG <group> <user>).
    for g in vouch-broker vouch-sms; do
      getent group "$g" >/dev/null || { groupadd --system "$g"; say "created group $g"; }
      id -nG "$SVC_USER" | tr ' ' '\n' | grep -qx "$g" || usermod -aG "$g" "$SVC_USER"
    done
    if [ -f "$ETC/vault.env" ]; then
      [ -s "$STATE/.vault-creds/role_id" ] && [ -s "$STATE/.vault-creds/secret_id" ] ||
        die "$ETC/vault.env is set but $STATE/.vault-creds/{role_id,secret_id} are missing (mode 0600, owned by $SVC_USER)"
    fi
  fi
}

install_files() {
  local src=$ROOT/$1/deploy/$INST
  install -d -m 0750 -o root -g "$SVC_USER" "$ETC"
  [ -e "$ETC/config.toml" ] || { install -m 0640 -o root -g "$SVC_USER" "$src/config.toml" "$ETC/config.toml"; say "wrote $ETC/config.toml (push notifications are off until you set [firebase] service_account_file)"; }
  if [ "$INST" = prod ] && [ ! -e "$ETC/secrets.env" ]; then
    install -m 0640 -o root -g "$SVC_USER" "$ROOT/$1/deploy/secrets.env.example" "$ETC/secrets.env"
    say "wrote $ETC/secrets.env (empty; fill it in if you turn SMS on)"
  fi
  install -m 0644 "$src/$UNIT.service" "/etc/systemd/system/$UNIT.service"
  # Vault is optional: with $ETC/vault.env present, a drop-in loads the
  # secrets from Vault at every start instead of from $ETC/secrets.env.
  # Releases before 0.3.4 carry their own Vault step in the unit and no drop-in.
  if [ "$INST" = prod ] && [ -f "$ETC/vault.env" ] && [ -f "$ROOT/$1/deploy/vault/vault.conf" ]; then
    install -d -m 0755 "/etc/systemd/system/$UNIT.service.d"
    install -m 0644 "$ROOT/$1/deploy/vault/vault.conf" "/etc/systemd/system/$UNIT.service.d/vault.conf"
  else
    rm -f "/etc/systemd/system/$UNIT.service.d/vault.conf"
  fi
  install -m 0755 "$src/$UNIT" "/usr/local/bin/$UNIT"
  systemctl daemon-reload
}

unpack() {
  local v=$1 tarball=$2 tmp
  install -d -m 0755 /opt/vouch "$ROOT"
  tmp=$(mktemp -d "$ROOT/.unpack.XXXXXX")
  tar -xzf "$tarball" -C "$tmp" --no-same-owner --no-same-permissions
  [ "$(cat "$tmp/vouch-server-$v/VERSION")" = "$v" ] || { rm -rf "$tmp"; die "the bundle is not version $v"; }
  if [ -d "$ROOT/$v" ]; then
    # A version is immutable: the same number from another commit is refused.
    if cmp -s "$tmp/vouch-server-$v/COMMIT" "$ROOT/$v/COMMIT"; then
      rm -rf "$tmp"
      say "$v is already unpacked"
      return
    fi
    rm -rf "$tmp"
    die "$ROOT/$v holds a different build of $v (commit $(cat "$ROOT/$v/COMMIT"))"
  fi
  chown -R root:root "$tmp/vouch-server-$v"
  chmod -R u=rwX,go=rX "$tmp/vouch-server-$v"
  mv "$tmp/vouch-server-$v" "$ROOT/$v"
  rmdir "$tmp"
}

link() { ln -sfn "$2" "$ROOT/.$1.new" && mv -T "$ROOT/.$1.new" "$ROOT/$1"; }

snapshot() {
  local from=$1 stamp f
  as_svc test -f "$DB" || return 0
  install -d -m 0700 -o root -g root "$BACKUPS"
  stamp="$BACKUPS/$from-$(date +%Y%m%dT%H%M%S)"
  for f in "" -wal -shm; do
    as_svc test -f "$DB$f" || continue
    (umask 077; as_svc cat "$DB$f" > "$stamp.db$f") || { rm -f "$stamp.db$f"; die "could not copy $DB$f"; }
  done
  say "database copied to $stamp.db"
  ls -1t "$BACKUPS"/*.db 2>/dev/null | tail -n +11 | while read -r old; do rm -f "$old" "$old-wal" "$old-shm"; done || true
}

# True when the database records a migration that release $1 does not have.
# Exits 0 for yes and 1 for no; anything else means it could not tell.
db_ahead_of() {
  as_svc test -f "$DB" || return 1
  as_svc node -e '
    try {
      const { DatabaseSync } = require("node:sqlite");
      const have = new Set(require("node:fs").readdirSync(process.argv[2]));
      const db = new DatabaseSync(process.argv[1], { readOnly: true });
      if (!db.prepare("SELECT 1 FROM sqlite_master WHERE type = ? AND name = ?").get("table", "migrations")) process.exit(1);
      process.exit(db.prepare("SELECT name FROM migrations").all().some((r) => !have.has(r.name)) ? 0 : 1);
    } catch (e) {
      console.error(String(e));
      process.exit(2);
    }
  ' "$DB" "$ROOT/$1/migrations"
}

restore_for() {
  local to=$1 copy f rc=0
  db_ahead_of "$to" || rc=$?
  [ "$rc" = 1 ] && return 0
  [ "$rc" = 0 ] || die "could not read which migrations $DB has, so it is not safe to start $to on it"
  copy=$(ls -1t "$BACKUPS/$to-"*.db 2>/dev/null | head -1)
  [ -n "$copy" ] || die "the database has migrations $to does not know, and there is no copy from $to in $BACKUPS to restore"
  for f in "" -wal -shm; do
    as_svc rm -f "$DB$f"
    [ -f "$copy$f" ] || continue
    as_svc sh -c 'umask 077; cat > "$1"' sh "$DB$f" < "$copy$f" || die "could not restore $DB$f from $copy$f"
  done
  say "restored the database from $copy: anything since then is gone"
}

healthy() {
  local v=$1
  for _ in $(seq 40); do
    curl -fsS --max-time 2 --unix-socket "$RUN/broker.sock" http://approver/healthz 2>/dev/null |
      jq -e --arg v "$v" '.version == $v' >/dev/null 2>&1 && return 0
    sleep 0.5
  done
  return 1
}

start_checked() {
  systemctl enable -q "$UNIT"
  systemctl restart "$UNIT"
  healthy "$1"
}

activate() {
  local v=$1 tarball=$2 cur prev
  setup_host
  unpack "$v" "$tarball"
  cur=$(version_of current)
  prev=$(version_of previous)
  install_files "$v"
  if [ "$cur" = "$v" ]; then
    start_checked "$v" || die "$v did not come up: journalctl -u $UNIT"
    say "$INST is on $v (restarted)"
    return
  fi
  systemctl stop "$UNIT" 2>/dev/null || true
  [ -n "$cur" ] && snapshot "$cur"
  link current "$v"
  [ -n "$cur" ] && link previous "$cur"
  if start_checked "$v"; then
    say "$INST is on $v${cur:+ (was $cur)}"
    prune
    return
  fi
  [ -n "$cur" ] || die "$v did not come up and there is nothing to go back to: journalctl -u $UNIT"
  say "$v did not come up; going back to $cur"
  systemctl stop "$UNIT"
  restore_for "$cur"
  link current "$cur"
  if [ -n "$prev" ]; then link previous "$prev"; else rm -f "$ROOT/previous"; fi
  install_files "$cur"
  start_checked "$cur" || die "$cur did not come up either: journalctl -u $UNIT"
  die "$v failed its health check; $INST is back on $cur"
}

rollback() {
  local cur prev
  cur=$(version_of current)
  prev=$(version_of previous)
  [ -n "$prev" ] && [ -d "$ROOT/$prev" ] || die "no previous release to go back to"
  systemctl stop "$UNIT"
  snapshot "$cur"
  restore_for "$prev"
  link current "$prev"
  link previous "$cur"
  install_files "$prev"
  start_checked "$prev" || die "$prev did not come up: journalctl -u $UNIT"
  say "$INST is back on $prev (was $cur)"
}

reset() {
  [ "$INST" = test ] || die "--reset is for the test instance only"
  local cur
  cur=$(version_of current)
  [ -n "$cur" ] || die "nothing installed"
  systemctl stop "$UNIT"
  as_svc rm -f "$DB" "$DB-wal" "$DB-shm"
  start_checked "$cur" || die "$cur did not come up: journalctl -u $UNIT"
  say "$INST reset: no devices, no requests"
}

prune() {
  local cur prev
  cur=$(version_of current)
  prev=$(version_of previous)
  ls -1t "$ROOT" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | grep -vxF -e "$cur" -e "${prev:-none}" | tail -n +$((KEEP - 1)) |
    while read -r old; do rm -rf "${ROOT:?}/$old"; say "removed old release $old"; done || true
}

status() {
  echo "$INST: current $(version_of current || true), previous $(version_of previous || true), unit $(systemctl is-active "$UNIT" 2>/dev/null || true)"
  ls -1 "$ROOT" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sed 's/^/  /' || true
}

as_root() { [ "$(id -u)" = 0 ] && "$@" || sudo "$0" "__$1" "$INST"; }

# Sourced by the tests, which call the functions above one at a time.
if [[ ${BASH_SOURCE[0]} != "$0" ]]; then return 0; fi

case ${1:-} in
  __activate) [ "$(id -u)" = 0 ] || die "internal"; instance "$2"; activate "$3" "$4" ;;
  __rollback) instance "$2"; rollback ;;
  __reset) instance "$2"; reset ;;
  *)
    instance "${1:-}"
    case ${2:-} in
      server-v*) fetch_and_install "$2" ;;
      --bundle) install_bundle "${3:?--bundle needs a file}" ;;
      --rollback) as_root rollback ;;
      --reset) as_root reset ;;
      --status) status ;;
      *) die "usage: deploy/install.sh <test|prod> server-vX.Y.Z | --bundle FILE | --rollback | --status | --reset" ;;
    esac
    ;;
esac
