# Vouch approver

The server half of Vouch: paired devices, pending approvals and push. Node 24
runs the TypeScript directly (type stripping), so there is no build step.

    npm ci
    npm test && npm run typecheck && npm run lint
    node src/main.ts --config config.example.toml   # needs write access to the paths in it

## Listeners

| Listener | Where | Who can reach it |
| --- | --- | --- |
| App API | TCP `app.host:app.port` (127.0.0.1:8770) | Anyone, through the tunnel. Every call but `/healthz` and pairing is signed by a paired device (`src/auth.ts`); unknown URLs are refused the same way. |
| Broker | `/run/vouch/broker.sock`, mode 0660, group `vouch-broker` | The broker's user, by group membership |
| Admin | `/run/vouch/admin.sock`, mode 0600 | The `vouch` user (the CLI runs as it) |

The kernel decides who may connect to a socket, through its file mode and group,
so a caller outside the group gets `EACCES` from `connect()` and never reaches
the service. Node has no `SO_PEERCRED`, so this stands in for a per-uid check; the effect is
the same for the one caller the broker socket has.

`GET /healthz` answers on all three.

The app API is rate limited per client address (120 a minute, using
`X-Forwarded-For` only from `app.trusted_proxies`) and per device (60 a minute),
answering 429 `rate_limited` with `Retry-After`.

## Logs

JSON lines on stdout (journald under systemd). Every line has `ts`, `service`,
`event` and `level`; later stories add `request_id`, `kind`, `agent`,
`device_id`, `outcome` and `latency_ms`. Usernames, passwords, push tokens and
setup tokens are never logged.

## Migrations

`migrations/NNNN_name.sql`, applied in order at startup and recorded with their
hash. They are append-only: editing or deleting an applied one stops startup.

## CLI

    npm run vouch -- setup-code     # QR and code for pairing a phone (10 minutes, one device)
    npm run vouch -- devices
    npm run vouch -- unpair <device_id>

It talks to the admin socket (`--socket`, default `/run/vouch/admin.sock`),
so run it as the `vouch` user. `setup-code` needs `app.public_url` set.

## Pairing

Each device pairs two P-256 keys: a **decision key** that signs only
decisions (and needs the user for every use when `policy.require_user_auth`
is on, the default) and a **transport key** that signs everything else.
`POST /v1/devices/pair` (app API) is signed by the transport key, and the
decision key proves possession by signing `vouch-pair-v1\n` + the setup token.

Android decision keys must come with a key attestation chain that ends at a
Google root (`src/data/google-attestation-roots.pem`, matched by key), names
the same key, carries SHA-256 of the setup token as its challenge, and is held
in TEE or StrongBox; with the policy on, the hardware must also say the key
needs the user for every use. A transport key attestation is checked when sent.
iOS devices are recorded as `client_asserted`: the server has no way to check
an iPhone's key, so with the policy on it still accepts one on the app's word
(see "Known limits" in `SECURITY.md`). The attestation revocation list is not
checked yet.

## Fake device

`tools/fake-device.ts` is a software phone: the reference client for the app
API, used by `test/fake-device.test.ts` and for testing without the app. Its
keys have no attestation, and it pairs as an Android device, so it pairs only
when `policy.require_user_auth` is false. (A client that said it was an iPhone
would pair either way, because iOS keys are not attested.) It keeps its keys and device id in `~/.vouch-fake-device.json` (0600).

    npm run fake-device -- pair --server http://127.0.0.1:8770 <setup token>
    npm run fake-device -- pending
    npm run fake-device -- decide <request_id> once|always|deny
    npm run fake-device -- watch once     # answer every new request, until stopped
    npm run fake-device -- checkin

## Releases and deploy

A tag `server-vX.Y.Z` on main (matching `package.json`) runs
`.github/workflows/release-server.yml`: lint, typecheck, tests and audit, then a
GitHub Release with `vouch-server-X.Y.Z.tar.gz` (built by `deploy/bundle.sh`: src,
migrations, deploy files and production `node_modules`, so the server needs no
npm) and its `.sha256`.

Requirements: Linux with systemd, Node 24, `curl`, `jq`, and `gh` able to read the
releases (or a bundle file). From a checkout:

    deploy/install.sh prod server-vX.Y.Z   # download, verify, install, switch, health-check
    deploy/install.sh prod --rollback      # back to the previous release
    deploy/install.sh prod --status
    deploy/install.sh prod --bundle FILE   # the same from a local bundle (deploy/bundle.sh)

`VOUCH_REPO=owner/repo` installs releases from a fork.

Releases unpack into `/opt/vouch/<test|prod>/<version>` with `current` and
`previous` symlinks; the last five are kept. Config (`/etc/vouch*/config.toml`)
is written from `deploy/<instance>/config.toml` once and left alone afterwards.
Before every switch the database is copied to `/var/backups/vouch` (`vouch-test`
for the test instance), which only root can read or write. The new version
must answer `/healthz` with its own version within 20 s or the previous one is
put back. Migrations run when the service starts, and older code refuses a
database with migrations it does not know, so a rollback across a migration
restores the copy taken when the older version was left (losing what happened
since). A version number is immutable: a different build of an installed
version is refused.

**prod** (`vouch`): the app API on `127.0.0.1:8770`, for a reverse proxy or
tunnel in front; the broker socket for group `vouch-broker` and the SMS socket
for group `vouch-sms`. The installer creates both groups; add your broker's user
and your texting agent's user to them. Secrets:

- The Firebase service account key: a JSON file named by
  `[firebase] service_account_file`, readable by `vouch`. A new install has it
  empty (no push), so the server starts before you have a key; put the key at
  `/etc/vouch/firebase.json`, name it there and restart.
- The SMS module's logins: `/etc/vouch/secrets.env` (written empty on first
  install from `deploy/secrets.env.example`).
- Or both from HashiCorp Vault at every start: see `deploy/vault/README.md`.

**test** (`vouch-test`): a second instance on port 8771 for trying things out,
with no push and no broker; `vouch-test send-test-request` stands in for one and
`vouch-test setup-code` makes pairing codes. It installs listening on this
machine only, with `policy.require_user_auth = true`. To reach it from a phone on
your network, set `[app] host = "0.0.0.0"` and `public_url` to the machine's LAN
address in `/etc/vouch-test/config.toml`; to pair the fake device, turn the
policy off. Both make it a test instance in earnest: don't point agents at it.

## Push

Firebase Cloud Messaging HTTP v1 (`src/fcm.ts`, no Google SDK): an OAuth
token minted from the service account in `firebase.service_account_file`,
then one high-priority data message per paired device carrying only
`{v, kind, id}`. A new approval pushes `request` to every device (and sets
`push_sent_at`); any end to it (decision, cancel, timeout) pushes `clear` to
every device except the one that answered. A token Firebase rejects marks the
device (`push_token_invalid_at`, a `push_token_invalid` log line) until the app
sends a new one with `PUT /v1/devices/me/push-token`. With no service account
configured nothing is sent and the service says so at startup.

The key is a JSON file named by `[firebase] service_account_file`, or loaded
from Vault at startup into `/run/vouch` (memory only); see
`deploy/vault/README.md`.
