# Claude Code in the Vouch repository

Two kinds of people open this repository with Claude Code: someone installing
Vouch for themselves, and someone changing the code. Ask which, if it isn't
clear from their first message.

## Helping someone install Vouch

Follow `INSTALL.md` with them, one step at a time, in order. For each step:
say what it does and why in a sentence, do or show the commands, then check it
worked before moving on (each step in `INSTALL.md` says how to check).

Ask before you start, in one message:

1. Which phones: iPhone, Android or both? (Decides the build path, and whether
   they need a Mac and an Apple developer account.)
2. Where will the server run, and does it have Docker?
3. How will the phone reach it: a VPN they already have, a domain for HTTPS, or
   Cloudflare?
4. Should agents sign in to websites with logins from 1Password? (That is the
   credential broker, step 6. It needs the systemd install, not Docker, and a
   1Password account. Skip it if not.)
5. Do they want SMS for their agent? (Most people don't; skip step 7 if not.)

Things only the person can do (open consoles, click buttons, sign in): give
exact menu paths and what to copy back, then wait. These include creating the
Firebase project, uploading the APNs key, downloading the service account key,
Xcode signing, installing the app on the phone, and, for the broker, creating
the 1Password vault and service account.

For the broker (step 6), follow `docs/broker.md` in order. Its installer and
`browser/setup` use sudo: say what each will do before running it.

Never:

- Commit or paste into chat the Firebase service account key, `GoogleService-Info.plist`,
  `google-services.json`, an APNs `.p8` key, keystores, `key.properties`,
  `secrets.env`, a 1Password service account token (`ops_...`), or any
  password. They are gitignored; keep it that way. Ask
  the person to put secret files in place themselves, or copy them with `scp`,
  and refer to them by path.
- Read `/etc/credbroker/secrets.env`, or make it readable by an agent's user.
  Have the person type the 1Password token into it themselves with `sudoedit`.
  An agent that can read a token can skip approval.
- Ask for a setup code to be sent anywhere other than to the person in front of
  you; it lets a phone approve their agents' requests.
- Open the app API to the internet without HTTPS, or turn off
  `policy.require_user_auth` outside a throwaway test instance.
- Change the person's firewall, VPN or DNS without saying exactly what and
  getting a yes first.

When something fails, check "When something doesn't work" in `INSTALL.md` and
the server log before guessing.

## Changing the code

Read `CONTRIBUTING.md` first. In short: one change per pull request, CI must
pass, and `api/openapi.yaml` is the contract between app and server: change it
only together with a regenerated app client (`app/tool/generate_api.sh`) and a
note if it breaks older apps. Server: `cd server && npm test`. App:
`cd app && flutter test`. Broker: `cd broker && uv run --frozen pytest -q`. Don't add hosts, names or paths from your own setup
to the code, docs or tests; use example values.
