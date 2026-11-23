# Installing Vouch

This guide takes you from nothing to an agent asking your phone for approval.
Plan on about an hour the first time, most of it in the Firebase and Apple or
Google consoles. If you use Claude Code, open this repository in it and say
"help me install Vouch": it follows this guide with you (see `CLAUDE.md`).

## What you'll end up with

- **The Vouch server** on a machine you control (a home server, a VM, a
  Raspberry Pi), next to the agents that will ask for approval.
- **The Vouch app** on your phone, built by you so that push notifications come
  from your own Firebase project.
- **A way for your phone to reach the server**: a VPN to your network, a
  reverse proxy with HTTPS, or Cloudflare Tunnel with Access.

There is no Vouch cloud service. Nothing here talks to the project's authors.

## What you need

| For | You need |
|---|---|
| The server | Linux with Docker, or Linux with systemd and Node 24 |
| Push notifications | A free Firebase project (a Google account) |
| An iPhone app | A Mac with Xcode and Flutter, and a paid Apple Developer Program membership (push notifications need it; a free team can't send them) |
| An Android app | Flutter and the Android SDK on any computer |
| Reaching the server | A VPN to your network, or a domain name for HTTPS, or a Cloudflare account |
| Signing agents in to websites (optional) | A 1Password account, and the systemd install of the server (not Docker) |
| SMS (optional) | A voip.ms account and an MQTT broker |

## 1. Firebase and the app

Follow **[docs/building-the-app.md](docs/building-the-app.md)**. It covers
choosing your app id, creating the Firebase project, giving Firebase your APNs
key for each iOS app, building, and installing on your phone. Keep the
**service account key** (a JSON file) it has you download: the server needs it
in the next step. Never commit it, or the Firebase config files, to git.

## 2. The server

Pick one.

**Docker (simplest).** Follow
**[server/deploy/docker/README.md](server/deploy/docker/README.md)**: copy the
folder, pin `VOUCH_VERSION`, set `[app] public_url`, put the service account key
next to it as `firebase.json`, and `docker compose up -d`.

**systemd.** On Debian or Ubuntu with Node 24, `curl`, `jq` and the GitHub
CLI (`gh`, signed in, to download the release):

```sh
git clone https://github.com/paulmona/vouch && cd vouch/server
deploy/install.sh prod server-vX.Y.Z      # the latest release
sudo install -m 0640 -o root -g vouch your-key.json /etc/vouch/firebase.json
sudoedit /etc/vouch/config.toml            # set [app] public_url, and [firebase]
                                           # service_account_file = "/etc/vouch/firebase.json"
sudo systemctl restart vouch
```

Details, including secrets from HashiCorp Vault, are in
[server/README.md](server/README.md).

**Check it:** `curl http://127.0.0.1:8770/healthz` answers
`{"ok":true,...}`.

### Trying Vouch without push

You can skip Firebase. A new server starts with push off, and the app knows:
it shows "open Vouch to check for requests" where it would otherwise rely on
notifications. Everything else works the same.

What changes without push:

- **Nothing tells you a request is waiting.** It appears when you open the app
  (or pull down to refresh), so you have to open it before the request expires.
  Have your agent tell you when it has asked, for example in its chat reply.
- The daily check that each phone is still reachable is off, since it works by
  push.

Add push later by putting the key in place, naming it in `[firebase]
service_account_file` and restarting; phones pick the change up the next time
the app opens.

## 3. Let your phone reach the server

The server listens on `127.0.0.1:8770` and speaks plain HTTP. Put one of these
in front of it, and set `[app] public_url` to the address the phone will use:

- **A VPN** (WireGuard, Tailscale) to your network, plus HTTPS from a reverse
  proxy on the server. The phone reaches Vouch only when the VPN is on. If the
  VPN carries only some addresses (split tunnel), include the server's.
- **A reverse proxy with HTTPS** (Caddy, nginx) on a domain that points at your
  network. The Docker setup includes Caddy behind a profile.
- **Cloudflare Tunnel and Access**: no open ports, and Cloudflare turns away
  anyone without your token. See
  [docs/cloudflare-access.md](docs/cloudflare-access.md).

Set `[app] trusted_proxies` to your proxy's address so rate limits see the
real client.

To test on your home network first, plain HTTP to the server's LAN address
works: the Docker README shows how to publish the port. Don't leave it that way.
The server and the app both refuse plain HTTP to anything but a private
address, a `.local` name or the same machine.

## 4. Pair your phone

```sh
vouch setup-code                           # systemd install
docker compose exec vouch vouch setup-code # Docker
```

Scan the QR code with the app, or paste the pairing link it prints. It works
once and for ten minutes. On iPhone, allow **Local Network** access when asked
if your server is on your home network (if you declined, turn it on under
Settings, Privacy & Security, Local Network). Pair each phone you want to approve
from; any of them can answer.

## 5. Connect an agent

Requests reach Vouch on a local socket that only root and the `vouch-broker`
group can open. Try it as root with the example client:

```sh
sudo examples/vouch-ask.py --agent "Test agent" --site example.com && echo approved
```

Your phone shows the request; approve it and the command prints `approved`.

Whatever is in `vouch-broker` chooses the agent name, site and login that your
phone shows, and can send alerts. So don't add an agent's own user to it: put
there the program that asks on the agent's behalf and that you trust to word
requests honestly. That is the credential broker in step 6, which adds itself,
or a broker of your own ([docs/agent-api.md](docs/agent-api.md)).

## 6. Sign agents in with your 1Password logins (optional)

The credential broker lets an agent sign in to a website with a login you keep
in 1Password. You approve each one on your phone, and the broker never hands
the password to the agent. An agent that goes looking in its own browser can
still read it, so give an agent only logins you would accept it knowing (see
"Known limits" in [SECURITY.md](SECURITY.md)). It needs the systemd install of
the server, on the same machine as your agents.

Follow **[docs/broker.md](docs/broker.md)**. Its steps, each with its own
check:

1. Install the broker (`broker/deploy/install.sh`).
2. Give each agent its own unix user and Chrome (`sudo browser/setup USER:PORT`).
3. In 1Password, make a vault and a read-only service account for each agent.
4. Put the token in `/etc/credbroker/secrets.env` and the agent in
   `/etc/credbroker/config.toml`.
5. Give the agent the tools (`claude mcp add ...`).

**Check it:** ask the agent to sign in to a site you made a login for. Your
phone asks; you approve; the agent is signed in.

The agent's user must not be your own login, must not be able to use sudo, and
must not be in the `vouch`, `credbroker`, `vouch-broker`, `docker` or `sudo`
groups. An agent with root, or with the `vouch` user's rights, can make a setup
code, pair a phone of its own and approve its own requests.

The agents themselves stay out of `vouch-broker`. If you added one while
trying things, take it out (`sudo gpasswd -d <user> vouch-broker`); the broker
installer warns about any it finds.

## 7. SMS for your agent (optional)

Turn on `[modules] sms`, fill in `[sms]` (your number, the owner's number, the
caps) and `[sms.voipms] did`, put the voip.ms API login and the MQTT login in
`/etc/vouch/secrets.env` (or your Docker `secrets.env`), and point your
voip.ms SMS webhook at something that publishes it to the `[sms.mqtt] topic`
(for example a Home Assistant automation). Add the agent's user to
`vouch-sms`. Every key is explained in
[server/config.example.toml](server/config.example.toml); the agent side is in
[docs/agent-api.md](docs/agent-api.md).

## When something doesn't work

- **No pairing code:** `[app] public_url` isn't set.
- **The app can't reach the server:** open `public_url` + `/healthz` in the
  phone's browser. If that fails, it's the network path in step 3. If the
  browser works but the app doesn't, on iPhone it's Local Network access
  (step 4); if the app never asked, restart the phone and try again.
- **No notifications on iPhone:** the APNs key isn't uploaded for that iOS app
  in Firebase (Project settings, Cloud Messaging), or the server has no
  service account key. The server log says `push_disabled_no_service_account`
  at startup in the second case.
- **A phone is lost or replaced:** on the server, run `vouch devices` to find
  the phone's id, then `vouch unpair <id>` (with Docker, put
  `docker compose exec vouch` in front of each). The server then sends that
  phone nothing and refuses its answers. Pair the new phone with a new setup
  code (step 4).
- **The app says "This phone no longer has its approval key. Forget this
  server in Settings, then pair again.":** the key that signs your answers is
  gone from the phone. Android deletes it when the screen lock is removed. Do
  what the message says. "Forget this server" does not tell the server, so
  also unpair the old entry there (`vouch devices`, then `vouch unpair <id>`)
  before or after you pair again with a new setup code.
- **A sign-in through the broker fails:** see "When something doesn't work"
  in [docs/broker.md](docs/broker.md).
- **"Permission denied" on a socket:** the user isn't in that socket's group
  yet (`credbroker-clients` for an agent that signs in through the credential
  broker, `vouch-sms` for one that texts, `vouch-broker` for a broker of your
  own), or its session hasn't restarted since it was added.

Logs: `journalctl -u vouch` (systemd) or `docker compose logs vouch`.
