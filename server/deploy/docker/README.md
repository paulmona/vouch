# Running Vouch with Docker

The quickest way to run the server. You still need your own build of the app,
and your own Firebase project if you want push notifications; see the install
guide.

1. Copy this folder to the machine that will run Vouch, somewhere it can stay
   (for example `/opt/vouch` or your NAS's app data share). The folder name
   becomes the Compose project name, which prefixes the volumes; pass
   `-p vouch` to every `docker compose` command if you want a fixed one.
2. Create `.env` next to `compose.yaml` with the release to run:
   `VOUCH_VERSION=X.Y.Z` (the latest `server-vX.Y.Z` release, without the
   `server-v`). Without it you get `latest`, which changes under you.
3. Edit `config.toml`: set `[app] public_url` to the address your phones will
   use, scheme, host and port if not the default (e.g.
   `https://vouch.example.com`).
4. Push notifications: save your Firebase project's service account key as
   `firebase.json` here, readable only by the container's user (uid 10001):
   `sudo chown 10001 firebase.json && sudo chmod 0400 firebase.json`. Don't
   make it world-readable: the key can send notifications as your project.
   **To run without push** (to try Vouch out), set
   `[firebase] service_account_file = ""` and delete the `firebase.json` line
   from `compose.yaml` (Docker would otherwise create an empty folder in its
   place). Approvals still work: open the app to see a waiting request.
5. If you use the SMS module, copy `secrets.env.example` to `secrets.env` and
   fill it in (`chmod 0600 secrets.env`; Compose reads it, the container
   doesn't need to).
6. Start it:
   - `docker compose up -d` serves plain HTTP on `127.0.0.1:8770`, for your own
     reverse proxy, VPN or Cloudflare Tunnel in front.
   - `VOUCH_DOMAIN=vouch.example.com docker compose --profile caddy up -d`
     adds Caddy, which gets a certificate and serves HTTPS on 443. You can
     put `VOUCH_DOMAIN` in `.env` instead. Vouch already trusts Caddy, and only
     Caddy, to report each phone's address: `compose.yaml` gives it a fixed
     address on a small private network (`10.87.70.0/29`; change it in
     `compose.yaml` and `config.toml` if that clashes with yours).
7. Check it: `curl http://127.0.0.1:8770/healthz` answers `{"ok":true,...}`
   (use your host port if you changed it).
8. Make a pairing code: `docker compose exec vouch vouch setup-code`, and scan it
   with the app.

**Trying it on your home network without HTTPS:** change the port line in
`compose.yaml` to `"8770:8770"` (or `"8780:8770"` for another host port) and set
`public_url = "http://<server's LAN address>:<host port>"`. Phones on the same
network can then pair. Anyone on your network can reach the server this way, so
use it to test, not to run.

**Image not found?** Until a release's image is published you can build it
yourself from a clone of the repository:
`docker build -t ghcr.io/paulmona/vouch-server:dev -f server/Dockerfile .` and set
`VOUCH_VERSION=dev`.

Data lives in the `vouch-data` volume (`/var/lib/vouch/vouch.db`); back it up.
To upgrade, change `VOUCH_VERSION` and `docker compose up -d` again: migrations
run on start, and an older image refuses a database a newer one has migrated, so
keep a backup before upgrading.

Times printed by `vouch setup-code` are in the container's time zone (UTC unless
you set `TZ` under `environment` in `compose.yaml`).

**Connecting a broker or agent outside Docker:** the agent sockets are in
`/run/vouch`. Bind that to a host folder (`./run:/run/vouch`), set
`[sockets] broker_group` to the numeric id of a host group your broker's user is
in, and add that id under `group_add`. The socket is then mode 0660 with that
group.

**Trying the example agent client** without Python on the host: run it in a
container that shares the socket volume, as Vouch's user:

```sh
docker run --rm --user 10001 -v vouch_vouch-run:/run/vouch \
  -v "$PWD/examples:/ex:ro" python:3.12-slim \
  python3 /ex/vouch-ask.py --agent "Test agent" --site example.com
```

(from a clone of the repository; the volume is `<project>_vouch-run`).
