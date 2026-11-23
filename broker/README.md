# credbroker

A credential broker for AI agents. It lets an agent sign in to a website with a
login the owner keeps in 1Password, without the broker handing the password to
the agent. An agent that goes looking in its own browser can still read it: see
"Known limits" in [`SECURITY.md`](../SECURITY.md).

Each agent is a unix user with its own 1Password vault and a read-only service
account for that vault. The broker holds the service account tokens. When an
agent asks to sign in, the broker reads the login from 1Password, asks the owner
to approve on their phone, and then types it into the agent's Chrome over the
DevTools port.

It runs on Linux with systemd only. There is no Docker image: the broker
identifies callers by their unix user and reaches each agent's Chrome on the
same machine, and a container would hide both.

Setting up each agent's Chrome, and restricting who can reach it, is in
[`browser/`](../browser/README.md).

## Install

You need:

- Linux with systemd, and Python 3.12 or 3.13 with venv and pip (on Debian and
  Ubuntu: `apt install python3-venv`). The 1Password SDK has no build for
  Python 3.14 yet, which is the only one Ubuntu 26.04 ships. There, install
  3.13 where every user can read it, for example with
  [uv](https://docs.astral.sh/uv/):
  `sudo UV_PYTHON_INSTALL_DIR=/opt/python uv python install 3.13`, and name it
  when you run the installer:
  `CREDBROKER_PYTHON=/opt/python/cpython-3.13-linux-x86_64-gnu/bin/python3.13 deploy/install.sh ...`
  (on upgrades too).
- The [GitHub CLI](https://cli.github.com/) (`gh`), signed in, to download the
  release.
- Vouch installed on the same machine first (see [`server/`](../server)). Its
  installer creates the `vouch-broker` group the broker needs. Without that
  group this installer still installs everything, but leaves the broker
  stopped and tells you to run it again once Vouch is in place.

From a checkout of this repository, as yourself (it uses sudo for the rest):

    broker/deploy/install.sh broker-vX.Y.Z

The installer:

- creates the system user `credbroker` and the group `credbroker-clients`, and
  adds `credbroker` to `vouch-broker`;
- downloads the release, checks its sha256, and unpacks it to
  `/opt/credbroker/<version>`, owned by root;
- builds a Python environment there with pip. Every package comes from PyPI and
  is checked against a hash that ships in the release;
- writes `/etc/credbroker/config.toml` and `/etc/credbroker/secrets.env` from
  the examples if they do not exist. It never overwrites them;
- adds every agent in `config.toml` to `credbroker-clients`;
- installs the systemd units, links `credbroker`, `credbroker-mcp` and
  `credbroker-leakcheck` into `/usr/local/bin`, starts the broker, and turns on
  the daily leak check.

After a first install the config file still holds the example agents and the
secrets file has empty tokens. The broker starts anyway, with nobody able to
sign in, and the installer prints what to edit next. See "Add an agent" below.

Set `VOUCH_REPO=owner/repo` to install releases from a fork.

### Upgrade and rollback

To upgrade, run the installer with the new tag. It is safe to run again with
the same tag. If the new version does not start, the installer puts the
previous one back and exits with an error.

To go back by hand:

    broker/deploy/install.sh --rollback

`broker/deploy/install.sh --status` shows the current and previous versions.
The installer keeps the last five.

`chrome-start` comes from `browser/setup`, not from this installer. After
upgrading it, restart each agent's browser once.

### Add an agent

1. Create the agent's unix user if it does not exist.
2. In `/etc/credbroker/config.toml`, add an `[agents.<user>]` table.
   [`config.example.toml`](config.example.toml) explains the fields.
3. In `/etc/credbroker/secrets.env`, set the agent's 1Password service account
   token under the name its `op_token_key` gives.
4. Add the user to the socket's group and restart the broker:

       sudo usermod -aG credbroker-clients <user>
       sudo systemctl restart credbroker

   Running the installer again does both.
5. Restart the agent's own session or service. A running process does not pick
   up a new group.
6. As that user, check it works:

       credbroker whoami

### Give Claude Code the tools

As the agent's user:

    claude mcp add -s user credbroker -- /usr/local/bin/credbroker-mcp

## What an agent can do

Agents use the `credbroker-mcp` MCP server, a thin client of the broker:

- `sign_in`: fill the login for the site open in the agent's browser.
- `begin_sign_in`, `fill_field`, `end_sign_in`: assisted sign-in for pages the
  automatic fill cannot cope with. The agent drives the page. The broker only
  types the secrets, into fields of the right type, on the matching site.
- `logins`: titles and websites of the logins in the agent's vault.
- `approvals`: the agent's standing approvals ("always allow").
- `revoke_my_approval`: ends one of the agent's own standing approvals. Agents
  can give access up; only the owner's phone can grant it.

## How a caller is identified

Agents connect to the unix socket `/run/credbroker/broker.sock` (mode 0660,
group `credbroker-clients`). The broker asks the kernel for the uid of the peer
(`SO_PEERCRED`) and looks it up in the config file. Anything in the request that
claims an identity is ignored. A uid that is not configured gets
`unknown_caller`. A user that is not in the group cannot open the socket at all.

## Configuration

The broker reads `/etc/credbroker/config.toml`. Set `CREDBROKER_CONFIG` to use
another path. It does not start without this file.
[`config.example.toml`](config.example.toml) explains every field: the agents,
where the daily leak check looks, and the optional MQTT events. Restart the
broker after a change: `sudo systemctl restart credbroker`.

A few settings are still environment variables: `CREDBROKER_SOCKET`,
`CREDBROKER_DB` and `CREDBROKER_VOUCH_SOCKET`.

The broker signs in only on a port the port guard says it is restricting to
that agent (`/run/vouch-browser/guarded`, written by `vouch-cdp-guard load`;
see `browser/README.md`). `CREDBROKER_GUARD_STATE` names another file; set it
empty only if you restrict the DevTools ports some other way.

## Secrets

The broker reads its secrets once at startup from `/etc/credbroker/secrets.env`
(or the path in `CREDBROKER_SECRETS`): `KEY=value` lines, owned by root with
group `credbroker` and mode 0640. The installer creates it that way.
[`secrets.env.example`](secrets.env.example) lists them: each agent's
1Password service account token, under the name `op_token_key` gives in the
config file, and the MQTT login if MQTT is used.

To keep them in HashiCorp Vault instead, follow
[`deploy/vault/README.md`](deploy/vault/README.md). In short: write
`/etc/credbroker/vault.env` with `VAULT_ADDR`, `CREDBROKER_VAULT_PATH` (the
secret's KV v2 API path, for example `secret/data/credbroker`) and
`CREDBROKER_VAULT_CREDS` (a directory holding the broker's AppRole `role_id` and
`secret_id`), then run the installer again. The broker reads that one secret
and revokes its Vault token straight away.

Agents must not be able to read these secrets. If they could, they could call
1Password themselves and skip approval.

## Approval

The owner approves through Vouch, the approval server in [`server/`](../server).
There is no other approval method. The broker creates the request on Vouch's
unix socket and long-polls it for the answer: once, always, deny or timeout.
Vouch sends the agent, site and login title to the owner's phone. The username
and reason stay in the broker.

The socket is `/run/vouch/broker.sock`, or the path in
`CREDBROKER_VOUCH_SOCKET`. The broker's unix user (`credbroker`) must be in
Vouch's `vouch-broker` group to open it.

Standing approvals ("always allow") are checked first. A sign-in covered by one
does not ask Vouch.

## Leak check

`credbroker-leakcheck` runs once a day, at 04:30 local time plus a random delay
of up to ten minutes, from the systemd timer `credbroker-leakcheck.timer`. If
the machine was off at that time, it runs at the next boot. It runs as root,
read-only, because it has to read every agent's home. It searches the files listed under
`[leakcheck]` in the config file, and the broker's journal, for any password or
security answer the agents can use. For each place it finds one, it logs an
error that names the login and the file, never the value, and it exits 3 if
everything was checked. It alerts the owner's phones
through Vouch: a notification, and in the app the list of logins and files. If
MQTT is on, it then also publishes one event; if that fails, the alert has
already gone and the check still ends as a leak.

The files it reads belong to the agents it is checking, so it never follows a
symbolic link an agent could have made (it follows one only in a folder that
root owns and nobody else can write to), reads only regular files, and does not
enter another filesystem mounted there. It keeps only a few folders open at a time, however deeply they
are nested. It has 20 minutes in all, shared
between the places it looks, so one agent's files cannot use up another's (given no wildcard in
`roots` below a folder an agent can write). If
one place runs out of time, has been replaced by a symbolic link or stops the
check with an error, if `roots` matches no folder at all, if 1Password does not
hand over one of the logins, if the broker's journal cannot be read to its end
(`journalctl` fails, or is not done in two minutes), or if the check
crashes, it exits 1, the unit shows as
failed, and your phone gets an alert naming what was not checked. Unless the
check crashed, anything found elsewhere is still reported. What was found in
the files is logged before the journal is read, as each place is done, and the
journal is read a piece at a time, so its size does not matter.

The check holds at most 200 places for each password or security answer in
each place it looks, each cut to the last 4,096 characters of its path, and
counts the rest, so an agent cannot use up its memory by giving one file many
thousands of names or by putting it very deep. If an error stops it once it
has started on the files, your
phone is told that a password was found (when one was) and that the check did
not finish, never that nothing was checked. The unit also has a memory limit
(`MemoryMax=`), and whatever ends it as failed (an exit other than 0 or 3, the
time limit, the memory limit, a kill) starts
`credbroker-leakcheck-failed.service`, which sends one alert with a fixed
text. It uses the Python standard library only and none of the check's code
or packages. It is run by the same Python and goes through Vouch like every
other alert, so it cannot cover a fault in either of those. A failed run that
sent its own alert brings this one too.

The alert fits in 2,000 characters. It opens with the number of places per
agent, then lists up to 20 places, one from each agent in turn, each cut to 150
characters that keep the end of the path. If it leaves places out, it ends with
"and N more, see the log". The log has up to 200 places for each password or
answer in each place the check looks, each with the last 4,096 characters of
its path, then the number of the rest.

### Test the leak check

`credbroker-leakcheck --canary` plants a fake secret first, to prove that the
check finds it and that the alert reaches your phone. It sends a real alert,
labelled "TEST canary (not a real login)". Set `canary_file` under
`[leakcheck]` in the config file (the example has a suggested path), then run
it as root, by hand:

    sudo credbroker-leakcheck --canary

With secrets in HashiCorp Vault, give it the Vault settings the service uses:

    sudo sh -c 'set -a; . /etc/credbroker/vault.env; exec credbroker-leakcheck --canary'

It exits 3, as it does for a real find, and removes the fake secret afterwards.
The alert stays in the app's Alerts list for 30 days.

## MQTT (optional)

MQTT is off by default, and the broker runs without it. To turn it on, add an
`[mqtt]` table with a `url` to the config file. The broker then publishes:

- one event per sign-in request to `event_topic` (default `credbroker/events`),
  with the agent, site, login title, reason, decision and timings;
- a retained heartbeat to `status_topic` (default `credbroker/status`): `up`
  every minute, and `down` when the broker stops;
- one event from the leak check when it finds something, with `kind` set to
  `leak`, the count of places, and up to 20 of the places, chosen and
  shortened as in the alert.

No event carries a username or a password. Set `ha_discovery = true` to announce
the heartbeat to Home Assistant as a connectivity sensor. Use an `mqtts://`
URL for TLS; with `mqtt://` the login travels in the clear. The MQTT login is optional and lives in the
secrets as `MQTT_USERNAME` and `MQTT_PASSWORD`.

## Run the tests

You need [uv](https://docs.astral.sh/uv/). The tests that drive a headless
browser need `google-chrome` on the PATH and are skipped without it. From
`broker/`:

    uv run --frozen pytest -q
    uvx ruff@0.8.6 check .

The full run takes under two minutes.
