#!/usr/bin/env bash
# Installs a credbroker release on this machine, or rolls one back. Run it as
# yourself from a checkout; it downloads with gh (which must be able to read this
# repo's releases, e.g. through GH_TOKEN) and uses sudo for the rest.
#
#   deploy/install.sh broker-vX.Y.Z   install that release and switch to it
#   deploy/install.sh --bundle FILE   the same from a local bundle (deploy/bundle.sh)
#   deploy/install.sh --rollback      switch back to the previous release
#   deploy/install.sh --status
#
# Needs Linux with systemd, and Python 3.12 or 3.13 with venv and pip
# (CREDBROKER_PYTHON names one other than python3). The
# Python packages come from PyPI, each checked against the hash in the release.
#
# Releases live in /opt/credbroker/<version>, each with its own venv, with
# `current` and `previous` symlinks. The new version must start and open its
# socket, or the previous one is put back. Existing files in /etc/credbroker are
# never overwritten. Safe to run again: it also picks up agents added to
# config.toml since the last run.
set -euo pipefail

REPO=${VOUCH_REPO:-paulmona/vouch}
KEEP=5
SVC_USER=credbroker
UNIT=credbroker
CLIENTS=credbroker-clients
VOUCH_GROUP=vouch-broker
ETC=/etc/credbroker
STATE=/var/lib/credbroker
RUN=/run/credbroker
ROOT=/opt/credbroker
SYSTEMD=/etc/systemd/system
PYTHON=${CREDBROKER_PYTHON:-python3}
die() { echo "install: $*" >&2; exit 1; }
say() { echo "install: $*"; }

version_of() { local l; l=$(readlink "$ROOT/$1" 2>/dev/null) && basename "$l" || true; }

check_host() {
  local c
  [ "$(uname -s)" = Linux ] && [ -d /run/systemd/system ] || die "credbroker needs Linux with systemd"
  for c in "$@" sha256sum tar "$PYTHON"; do
    command -v "$c" >/dev/null || die "$c is not installed"
  done
  # The 1Password SDK is published only as built packages, for 3.12 and 3.13.
  "$PYTHON" -c 'import sys; sys.exit(not (3, 12) <= sys.version_info[:2] <= (3, 13))' 2>/dev/null ||
    die "$PYTHON is $("$PYTHON" -V 2>&1); credbroker needs Python 3.12 or 3.13 (the 1Password SDK has no build for others). Install one and name it: CREDBROKER_PYTHON=/path/to/python3.13 deploy/install.sh ..."
  "$PYTHON" -c 'import venv, ensurepip' 2>/dev/null ||
    die "$PYTHON has no venv and pip (on Debian and Ubuntu: apt install python3-venv)"
}

# sudo drops the environment, so the chosen Python is passed on by name.
as_root() { if [ "$(id -u)" = 0 ]; then "$@"; else sudo CREDBROKER_PYTHON="$PYTHON" "$@"; fi; }

# --- as yourself ---------------------------------------------------------

fetch_and_install() {
  local tag=$1 v
  [[ $tag =~ ^broker-v([0-9]+\.[0-9]+\.[0-9]+)$ ]] || die "not a broker release tag: $tag"
  v=${BASH_REMATCH[1]}
  check_host gh
  # Global, not local: the EXIT trap runs after this function has returned.
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  gh release download "$tag" -R "$REPO" -D "$tmp" -p "credbroker-$v.tar.gz" -p "credbroker-$v.tar.gz.sha256"
  (cd "$tmp" && sha256sum --quiet -c "credbroker-$v.tar.gz.sha256") || die "checksum mismatch for $tag"
  as_root "$0" __activate "$v" "$tmp/credbroker-$v.tar.gz"
}

install_bundle() {
  local file=$1 v
  [[ $(basename "$file") =~ ^credbroker-([0-9]+\.[0-9]+\.[0-9]+)\.tar\.gz$ ]] || die "not a bundle: $file"
  v=${BASH_REMATCH[1]}
  check_host
  (cd "$(dirname "$file")" && sha256sum --quiet -c "$(basename "$file").sha256") || die "checksum mismatch for $file"
  as_root "$0" __activate "$v" "$(cd "$(dirname "$file")" && pwd)/$(basename "$file")"
}

# --- as root -------------------------------------------------------------

in_group() { id -nG "$1" | tr ' ' '\n' | grep -qx "$2"; }

setup_host() {
  local creds
  getent group "$CLIENTS" >/dev/null || { groupadd --system "$CLIENTS"; say "created group $CLIENTS"; }
  if ! id "$SVC_USER" >/dev/null 2>&1; then
    useradd --system --user-group --no-create-home --home-dir "$STATE" --shell /usr/sbin/nologin "$SVC_USER"
    say "created user $SVC_USER"
  fi
  install -d -m 0750 -o "$SVC_USER" -g "$SVC_USER" "$STATE"
  # Vouch's installer creates vouch-broker; membership lets the broker open Vouch's socket.
  if getent group "$VOUCH_GROUP" >/dev/null; then
    in_group "$SVC_USER" "$VOUCH_GROUP" || { usermod -aG "$VOUCH_GROUP" "$SVC_USER"; say "added $SVC_USER to $VOUCH_GROUP"; }
  fi
  if [ -f "$ETC/vault.env" ]; then
    creds=$(sed -n 's/^[[:space:]]*CREDBROKER_VAULT_CREDS=//p' "$ETC/vault.env" | tail -1)
    [ -n "$creds" ] || die "$ETC/vault.env does not set CREDBROKER_VAULT_CREDS"
    [ -s "$creds/role_id" ] && [ -s "$creds/secret_id" ] ||
      die "$ETC/vault.env is set but $creds/{role_id,secret_id} are missing (mode 0600, owned by $SVC_USER)"
  fi
}

install_files() {
  local rel=$ROOT/$1 u
  install -d -m 0750 -o root -g "$SVC_USER" "$ETC"
  [ -e "$ETC/config.toml" ] || { install -m 0640 -o root -g "$SVC_USER" "$rel/config.example.toml" "$ETC/config.toml"; say "wrote $ETC/config.toml (the example: edit it)"; }
  [ -e "$ETC/secrets.env" ] || { install -m 0640 -o root -g "$SVC_USER" "$rel/secrets.env.example" "$ETC/secrets.env"; say "wrote $ETC/secrets.env (empty: fill it in)"; }
  install -m 0644 "$rel/deploy/$UNIT.service" "$rel/deploy/$UNIT-leakcheck.service" "$rel/deploy/$UNIT-leakcheck.timer" "$SYSTEMD/"
  # A release from before the failure unit has none, and its leak-check unit
  # names none. Going back to one must not stop here: the broker is down.
  if [ -f "$rel/deploy/$UNIT-leakcheck-failed.service" ]; then
    install -m 0644 "$rel/deploy/$UNIT-leakcheck-failed.service" "$SYSTEMD/"
  else
    rm -f "$SYSTEMD/$UNIT-leakcheck-failed.service"
  fi
  # Vault is optional: with $ETC/vault.env present, a drop-in makes the broker
  # and the leak check read the secrets from Vault instead of $ETC/secrets.env.
  for u in "$UNIT" "$UNIT-leakcheck"; do
    if [ -f "$ETC/vault.env" ] && [ -f "$rel/deploy/vault/vault.conf" ]; then
      install -d -m 0755 "$SYSTEMD/$u.service.d"
      install -m 0644 "$rel/deploy/vault/vault.conf" "$SYSTEMD/$u.service.d/vault.conf"
    else
      rm -f "$SYSTEMD/$u.service.d/vault.conf"
    fi
  done
  for u in credbroker credbroker-mcp credbroker-leakcheck; do
    ln -sfn "$ROOT/current/venv/bin/$u" "/usr/local/bin/$u"
  done
  systemctl daemon-reload
}

# One "user token-key" line per agent in config.toml; the key is - when the agent has none.
agents() {
  "$PYTHON" -c '
import sys, tomllib
with open(sys.argv[1], "rb") as f:
    for name, a in tomllib.load(f).get("agents", {}).items():
        print(name, a.get("op_token_key") or "-")
' "$ETC/config.toml"
}

# The socket is open to credbroker-clients only, so every agent has to be in it.
add_agents() {
  local list a key
  list=$(agents) || die "cannot read $ETC/config.toml"
  while read -r a key; do
    [ -n "$a" ] || continue
    if ! id "$a" >/dev/null 2>&1; then
      say "agents.$a: no such user on this machine, skipped"
    elif ! in_group "$a" "$CLIENTS"; then
      usermod -aG "$CLIENTS" "$a"
      say "added $a to $CLIENTS: restart that agent's session or service so it picks the group up"
    fi
  done <<<"$list"
}

# What is left for the owner to do. Names keys, never values.
next_steps() {
  local list a key n=0
  list=$(agents) || return 0
  while read -r a key; do
    [ -n "$a" ] && id "$a" >/dev/null 2>&1 || continue
    n=$((n + 1))
    [ "$key" = - ] && continue
    # Anything in Vouch's group can word its own requests and alerts on the owner's phone.
    if in_group "$a" "$VOUCH_GROUP"; then
      say "warning: $a is an agent and is in $VOUCH_GROUP, so it can put requests and alerts of its own"
      say "         wording on your phone. Only $SVC_USER needs that group: sudo gpasswd -d $a $VOUCH_GROUP"
    fi
    [ -f "$ETC/vault.env" ] && continue
    grep -Eq "^[[:space:]]*${key}[[:space:]]*=[[:space:]]*[^[:space:]]" "$ETC/secrets.env" ||
      say "next: $a has no 1Password token yet. Set $key in $ETC/secrets.env, then: sudo systemctl restart $UNIT"
  done <<<"$list"
  if [ "$n" = 0 ]; then
    say "next: no agent in $ETC/config.toml is a user on this machine, so nobody can sign in yet."
    say "      Give each agent's unix user an [agents.<user>] table there and its token in"
    say "      $ETC/secrets.env, then run this installer again."
  fi
  if ! getent group "$VOUCH_GROUP" >/dev/null; then
    say "next: there is no $VOUCH_GROUP group, so Vouch is not installed on this machine yet."
    say "      credbroker cannot start without it and has been left stopped."
    say "      Install the Vouch server (server/deploy/install.sh), then run this installer again."
  fi
}

build_venv() {
  local rel=$ROOT/$1
  "$PYTHON" -m venv "$rel/venv" &&
    "$rel/venv/bin/pip" install -q --disable-pip-version-check --no-cache-dir \
      --only-binary :all: --require-hashes -r "$rel/requirements.txt" &&
    "$rel/venv/bin/pip" install -q --disable-pip-version-check --no-cache-dir \
      --no-index --no-deps "$rel"/credbroker-"$1"-*.whl
}

unpack() {
  local v=$1 tarball=$2 tmp
  install -d -m 0755 "$ROOT"
  tmp=$(mktemp -d "$ROOT/.unpack.XXXXXX")
  tar -xzf "$tarball" -C "$tmp" --no-same-owner --no-same-permissions
  [ "$(cat "$tmp/credbroker-$v/VERSION")" = "$v" ] || { rm -rf "$tmp"; die "the bundle is not version $v"; }
  if [ -d "$ROOT/$v" ]; then
    # A version is immutable: the same number from another commit is refused.
    if cmp -s "$tmp/credbroker-$v/COMMIT" "$ROOT/$v/COMMIT"; then
      rm -rf "$tmp"
      say "$v is already unpacked"
      return
    fi
    rm -rf "$tmp"
    die "$ROOT/$v holds a different build of $v (commit $(cat "$ROOT/$v/COMMIT"))"
  fi
  chown -R root:root "$tmp/credbroker-$v"
  chmod -R u=rwX,go=rX "$tmp/credbroker-$v"
  # A venv cannot be moved, so it is built in place and the release removed if that fails.
  mv "$tmp/credbroker-$v" "$ROOT/$v"
  rmdir "$tmp"
  say "building the Python environment for $v"
  build_venv "$v" || { rm -rf "${ROOT:?}/$v"; die "could not build the Python environment for $v"; }
}

link() { ln -sfn "$2" "$ROOT/.$1.new" && mv -T "$ROOT/.$1.new" "$ROOT/$1"; }

# The broker opens its socket only after it has read the config and the secrets.
healthy() {
  for _ in $(seq 40); do
    systemctl is-active -q "$UNIT" && [ -S "$RUN/broker.sock" ] && return 0
    sleep 0.5
  done
  return 1
}

# systemd refuses to start a unit whose SupplementaryGroups names a missing
# group, and would retry forever. Without Vouch's group the unit is left
# disabled; next_steps says so.
start_checked() {
  if ! getent group "$VOUCH_GROUP" >/dev/null; then
    systemctl disable -q "$UNIT" 2>/dev/null || true
    return 0
  fi
  systemctl enable -q "$UNIT"
  systemctl restart "$UNIT"
  healthy
}

finish() {
  systemctl enable -q --now "$UNIT-leakcheck.timer"
  next_steps
}

activate() {
  local v=$1 tarball=$2 cur prev
  setup_host
  unpack "$v" "$tarball"
  cur=$(version_of current)
  prev=$(version_of previous)
  install_files "$v"
  add_agents
  if [ "$cur" = "$v" ]; then
    start_checked || die "$v did not come up: journalctl -u $UNIT"
    say "credbroker is on $v (restarted)"
    finish
    return
  fi
  systemctl stop "$UNIT" 2>/dev/null || true
  link current "$v"
  [ -n "$cur" ] && link previous "$cur"
  if start_checked; then
    say "credbroker is on $v${cur:+ (was $cur)}"
    prune
    finish
    return
  fi
  [ -n "$cur" ] || die "$v did not come up and there is nothing to go back to: journalctl -u $UNIT"
  say "$v did not come up; going back to $cur"
  systemctl stop "$UNIT"
  link current "$cur"
  if [ -n "$prev" ]; then link previous "$prev"; else rm -f "$ROOT/previous"; fi
  install_files "$cur"
  start_checked || die "$cur did not come up either: journalctl -u $UNIT"
  die "$v failed to start; credbroker is back on $cur"
}

rollback() {
  local cur prev
  cur=$(version_of current)
  prev=$(version_of previous)
  [ -n "$prev" ] && [ -d "$ROOT/$prev" ] || die "no previous release to go back to"
  systemctl stop "$UNIT"
  link current "$prev"
  link previous "$cur"
  install_files "$prev"
  start_checked || die "$prev did not come up: journalctl -u $UNIT"
  say "credbroker is back on $prev (was $cur)"
}

prune() {
  local cur prev
  cur=$(version_of current)
  prev=$(version_of previous)
  # shellcheck disable=SC2010  # newest first, and release names are plain version numbers
  ls -1t "$ROOT" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | grep -vxF -e "$cur" -e "${prev:-none}" | tail -n +$((KEEP - 1)) |
    while read -r old; do rm -rf "${ROOT:?}/$old"; say "removed old release $old"; done || true
}

status() {
  echo "credbroker: current $(version_of current || true), previous $(version_of previous || true), unit $(systemctl is-active "$UNIT" 2>/dev/null || true)"
  find "$ROOT" -mindepth 1 -maxdepth 1 -type d -regex '.*/[0-9]+\.[0-9]+\.[0-9]+' -printf '  %f\n' 2>/dev/null | sort -V || true
}

# Sourced by the tests, which call the functions above one at a time.
if [[ ${BASH_SOURCE[0]} != "$0" ]]; then return 0; fi

case ${1:-} in
  __activate) [ "$(id -u)" = 0 ] || die "internal"; umask 022; activate "$2" "$3" ;;
  __rollback) [ "$(id -u)" = 0 ] || die "internal"; umask 022; rollback ;;
  broker-v*) fetch_and_install "$1" ;;
  --bundle) install_bundle "${2:?--bundle needs a file}" ;;
  --rollback) as_root "$0" __rollback ;;
  --status) status ;;
  *) die "usage: deploy/install.sh broker-vX.Y.Z | --bundle FILE | --rollback | --status" ;;
esac
