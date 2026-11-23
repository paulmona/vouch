# Vouch

**Let your AI agents use the web as you, with approved access to a 1Password vault on every login.**

Created by Paul Monaghan, [Viewbridge AI](https://viewbridge.ai).

Vouch is a self-hosted system that gives an AI agent a real browser and a way
to sign in to your accounts that you approve each time. The agent asks to sign
in; your phone shows the request; you approve with your fingerprint or Face ID;
the login is typed into the agent's browser straight from your 1Password. The
broker never hands the password to the agent. An agent that goes looking in its
own browser can still read it (see "Known limits" in
[SECURITY.md](SECURITY.md)).

Everything runs on your own server, next to your custom Claude agent(s).

## What's in it

| Part | What it does |
| --- | --- |
| **A browser for each agent** | Each agent gets its own Google Chrome with its own profile, so it stays signed in between tasks. A firewall rule keeps other unix users on the machine off the browser's control port: only that agent and the broker may connect. Root still can (see "Known limits" in [SECURITY.md](SECURITY.md)). |
| **Credential broker** | Holds a read-only 1Password service account for each agent. When an agent asks to sign in, it finds the matching login, asks you through the Vouch mobile app for approval, and types the login into the page itself. It fills a login only on the site the login belongs to. The broker never hands the password to the agent; an agent that goes looking in its own browser can still read it (see "Known limits" in [SECURITY.md](SECURITY.md)). |
| **MCP tools for the agent** | `sign_in`, assisted sign-in for awkward pages, `logins` and `approvals`. They work with Claude Code or any agent (only tested with Claude) that speaks MCP. |
| **Vouch server** | Keeps the paired phones and the pending requests, and checks every answer. Agents and the broker reach it over local sockets only. |
| **Phone app** (iPhone and Android) | Shows each request full screen: which agent, which site, which login. **Approve once**, **Always allow** or **Deny**. Your answer is signed by a key in the phone's secure hardware that needs your fingerprint or Face ID. |
| **SMS for an agent** (optional) | Gives an agent its own phone number. You see every conversation in the app and approve who it may text. |

## How a sign-in works

```
 agent ──"sign me in to example.com"──▶ broker ──"may it?"──▶ Vouch ──push──▶ your phone
   │                                      │  ▲                  ▲                 │
   │ drives                  reads login  │  └──── approved ────┴── signed answer ┘
   ▼                    before it asks    ▼
 its own Chrome ◀──── types the login ── 1Password
```

1. The agent opens a site's login page in its Chrome and calls `sign_in`.
2. The broker finds the login for that site in the agent's 1Password vault and
   reads it.
3. Your phone shows the request, unless you already chose **Always allow** for
   that agent and that login.
4. You approve. The broker types the login into the page.
5. The agent carries on, signed in. No username or password is ever returned
   to it.

## What you control

- **Which logins each agent can use at all.** Each agent has its own 1Password
  vault; you put in it only what that agent may use.
- **Every sign-in**, from your phone, with a biometric check. **Always
  allow** lets one agent use one login without asking again; you list and
  revoke those on the server ([how](docs/broker.md#standing-approvals)).
- **Where it runs.** The server, broker and browsers are on your machine. Push
  notifications go through your own Firebase project and carry only ids.

What it does not do: limit what an agent does once it is signed in. It can do
anything that account can do on that site, so approve a sign-in only for an
agent you would trust with the account. [SECURITY.md](SECURITY.md) says exactly
what is and isn't protected, including what the server can verify about a
phone.

## Use just the parts you want

- **Approvals only.** A tool you trust can ask your phone a yes or no question
  over a local socket, without the broker or 1Password: a few lines of HTTP,
  or the one-file client `examples/vouch-ask.py`. Whatever opens that socket
  chooses what your phone shows, so run the tool as its own user and keep the
  agent's user out of the socket's group. See
  [docs/agent-api.md](docs/agent-api.md).
- **Your own broker.** The socket contract is in
  [api/broker.yaml](api/broker.yaml), and the broker here is a working
  reference.
- **Your own browser.** Any Chrome or Chromium with a DevTools port works with
  the broker; see [browser/README.md](browser/README.md).

## Get started

**Start with [INSTALL.md](INSTALL.md).** With Claude Code, open this
repository and say "help me install Vouch": it follows the guide with you.

You will need:

- a Linux machine for the server and your agents (systemd for the full system;
  Docker works for the server alone);
- to build the phone app yourself, against your own free Firebase project (an
  iPhone build needs a Mac and a paid Apple developer membership);
- a way for your phone to reach the server: a VPN, a reverse proxy with HTTPS,
  or Cloudflare Tunnel with Access;
- a 1Password account, for agent sign-ins.

Get it running fast by downloading the app from the app store (push notifications
not enabled), or compile the app yourself and enable push via Firebase.

## In this repository

| Path | What |
| --- | --- |
| `server/` | The Vouch server (Node 24, TypeScript, Fastify, SQLite). |
| `app/` | The phone app (Flutter). |
| `broker/` | The credential broker and its MCP server (Python). |
| `browser/` | Chrome for each agent, and the guard on its DevTools port. |
| `api/` | The contracts: app to server (`openapi.yaml`) and agent to server (`broker.yaml`). |
| `docs/` | Guides: [building the app](docs/building-the-app.md), [the broker and 1Password](docs/broker.md), [connecting an agent](docs/agent-api.md), [Cloudflare Access](docs/cloudflare-access.md). |
| `examples/` | A one-file client for the approval socket, and instructions to give an agent that signs in through the broker. |

## Status

Early. Vouch runs daily for its author's own agents, but expect rough edges in
setup. Supported today: Debian and Ubuntu on amd64 for the broker and browser;
the server also runs in Docker.

## Contributing and security

See [CONTRIBUTING.md](CONTRIBUTING.md). Report vulnerabilities privately as
described in [SECURITY.md](SECURITY.md).

## Licence

Apache License 2.0. Copyright 2026 Paul Monaghan (Viewbridge AI). See
[LICENSE](LICENSE) and [NOTICE](NOTICE).

The licence does not cover the Vouch name or logo, and Vouch is not affiliated
with 1Password, Apple, Cloudflare or Google: see [NOTICE](NOTICE).
