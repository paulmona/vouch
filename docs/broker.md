# Signing agents in: the credential broker

With the broker, an agent can sign in to a website using a login you keep in
1Password, after you approve on your phone, without the password being given to the
agent. (An agent that sets out to take it from its own browser can: see
"Known limits" in `SECURITY.md`.)

How one sign-in goes:

1. The agent opens the site's login page in its own Chrome and calls the
   `sign_in` tool.
2. The broker looks in that agent's 1Password vault for a login whose website
   matches the page, and reads it.
3. Unless you have already said "Always allow" for that login, Vouch shows the
   request on your phone: which agent, which site, which login. You answer with
   your fingerprint or Face ID.
4. On approval the broker types the login into the page. The agent is told
   `signed_in`. It never receives the username or the
   password.
5. If you approved once, the broker also tells the agent to sign out of the
   site when its task is done. It cannot make the agent do so: until the agent
   signs out or the site ends the session, the agent can use the site without
   asking you again (see "Known limits" in `SECURITY.md`).

You need Vouch installed and a phone paired first (steps 1 to 4 of
[INSTALL.md](../INSTALL.md)), on the same Linux machine as your agents, and a
1Password account. The broker runs under systemd only, not in Docker.

Each step below ends with a check. Don't go on until it passes.

## 1. Install the broker

Follow the Install section of [broker/README.md](../broker/README.md). In
short, from a clone of this repository:

```sh
broker/deploy/install.sh broker-vX.Y.Z     # the latest broker release
```

The broker needs Python 3.12 or 3.13; the README says what to do on systems
that ship only 3.14, such as Ubuntu 26.04.

**Check:** `broker/deploy/install.sh --status` shows the version and
`unit active`.

## 2. Give each agent a unix user and a browser

Each agent runs as its own unix user. That is how the broker tells agents
apart, so two agents must not share one. Create the user if you don't have
one, then set up its Chrome and lock
down its DevTools port, as [browser/README.md](../browser/README.md) describes.

The agent's user must not be your own login, must not be able to use sudo, and
must not be in the `vouch`, `credbroker`, `vouch-broker`, `docker` or `sudo`
groups. An agent with root, or with the `vouch` user's rights, can make a setup
code, pair a phone of its own and approve its own requests.

```sh
sudo adduser --disabled-password research   # if the user does not exist yet
sudo browser/setup research:9222
```

**Check:** as the agent's user, `chrome-start` prints Chrome's version details.
As any other non-root user, `curl http://127.0.0.1:9222/json/version` is
refused.

## 3. A 1Password vault and service account for each agent

Do this in 1Password; only you can.

1. **Create a vault for the agent**, for example "Research agent". Put in it
   only the logins this agent may use. Don't use your personal vault: a service
   account can't read it, and the agent should not have everything.
2. **Create a service account** that can **read** that one vault and nothing
   else, with no write access. 1Password's guide is at
   <https://developer.1password.com/docs/service-accounts/>. The vaults a
   service account can reach are fixed when you create it.
3. **Copy the token** it shows (it starts with `ops_`). 1Password shows it
   once. Don't paste it into a chat with an agent, a ticket or a shell history.

One vault and one service account per agent. The broker refuses a token that
can see more than one vault.

For each login in the vault:

- It must be a **Login** item, with the site's address in its **website**
  field. The broker fills a login only on a page that matches a website on the
  item, following the item's own autofill setting: anywhere on that website
  (the default: the same domain and its subdomains), only on the exact domain,
  or never. A setting the broker does not know is treated as never. With the
  1Password SDK the broker is locked to (0.4.2) it does not get that far: the
  SDK refuses the whole list of the vault's items if one of them has a
  setting the SDK does not know, so every sign-in for that agent fails with
  `fill_failed` until the broker is updated. Either way nothing is typed.
  This is what stops a lookalike site.
- Answers to security questions go in extra **password-type fields**, each
  labelled with the question exactly as the site asks it.
  The broker offers every password-type field on the item, other than the
  password itself, as such an answer: the agent names the question, and the
  broker may type the matching field into an ordinary text field, where the
  agent can read it. In an ordinary sign-in the broker picks the field itself,
  from the text of the page the site shows after the password. Keep recovery
  codes and other secrets off the item.
- A login with no password (the site emails or texts a code) works through
  assisted sign-in: the broker types the username and the agent types the code.

## 4. Tell the broker about the agent

1. Put the token in `/etc/credbroker/secrets.env`, under a name you choose:

   ```sh
   sudoedit /etc/credbroker/secrets.env
   ```
   ```
   OP_TOKEN_RESEARCH=ops_...
   ```

   The file is readable by root and the broker only. Agents must never be able
   to read it: with the token they could ask 1Password themselves and skip your
   approval. To keep tokens in HashiCorp Vault instead, see
   [broker/deploy/vault/README.md](../broker/deploy/vault/README.md).

2. Add the agent to `/etc/credbroker/config.toml`, replacing the examples. The
   table name is the unix user, and `cdp_port` is the port from step 2:

   ```toml
   [agents.research]
   op_token_key = "OP_TOKEN_RESEARCH"
   cdp_port = 9222
   ```

3. Run the installer again with the same tag. It adds the user to the broker's
   group, restarts the broker and lists anything still missing.
4. Restart the agent's own session or service, so it picks up its new group.

**Check:** as the agent's user, `credbroker whoami` names the agent, and
`credbroker logins` lists the titles and websites of the logins in its vault.
`vault_unavailable` means the token is missing or wrong, or it sees more or
fewer than one vault.

## 5. Give the agent the tools

The agent uses the broker through an MCP server, `credbroker-mcp`. For Claude
Code, as the agent's user:

```sh
claude mcp add -s user credbroker -- /usr/local/bin/credbroker-mcp
```

Any agent that speaks MCP can run the same command as a stdio server.

The server tells the agent how to use its browser when it connects: start it
with `chrome-start`, attach to it (never launch another), open the login page,
then call `sign_in`. An agent that offers some other browser tool, such as a
browser extension, has not picked that up: point it at `chrome-start`.

How the agent should behave around your accounts is yours to say: when to sign
in, what to do when you deny a request, leaving your sessions alone.
[examples/agent-instructions.md](../examples/agent-instructions.md) has a
section to paste into the agent's own instructions.

| Tool | What it does |
|---|---|
| `sign_in` | Fills the login for the page open in the agent's browser, after approval. Returns `signed_in`, `denied`, `timeout`, `no_login`, `site_mismatch` or `fill_failed`. After an approval for once, the reply carries a `sign_out` note telling the agent to sign out when the task is done. |
| `begin_sign_in`, `fill_field`, `end_sign_in` | Assisted sign-in, for pages the automatic fill can't handle (several steps, security questions, code-only logins). The agent drives the page; the broker types each secret, and only into a field of the right kind on the matching site. |
| `logins` | Titles and websites of the logins in the agent's vault. Never usernames or passwords. |
| `approvals` | The agent's standing approvals. |
| `revoke_my_approval` | Ends one of the agent's own standing approvals. It can't grant one. |

An agent marked `admin = true` in the config also gets tools to list every
agent's standing approvals and to revoke one. It can't grant them.

**Check:** ask the agent to open a site you made a login for and sign in. Your
phone shows the request; approve it; the agent reports it is signed in. No
reply it received holds the password.

## Standing approvals

**Always allow** on the phone lets that agent use that one login from then on
without asking. The broker keeps the list; a standing approval ends when you
revoke it or when the login leaves the agent's vault.

The simplest way to end one is to ask the agent: "stop using the Example login
without asking me". It revokes its own standing approval, and your phone is
asked again from the next sign-in. A session already open on that site stays
signed in.

That relies on the agent doing as it is told. To see and revoke them yourself,
whatever the agent does, give your own unix user an entry with `admin = true` and no
token (so it has no logins), then run the installer again and sign in afresh:

```toml
[agents.alex]
admin = true
```
```sh
credbroker approvals --all                    # every agent's
credbroker revoke research "Example login"
```

Nobody can grant a standing approval from the command line: that takes your
phone.

## The daily leak check

Once a day `credbroker-leakcheck` searches the agents' files (by default
`/home/*/.claude` and the broker's own data) and the broker's journal for any
password or security answer the agents can use. If one turns up, something put
a secret where the agent can read it. The check alerts your phone through
Vouch, and logs which login and which file, never the value. If the check
itself fails or cannot finish, your phone gets an alert saying so, and the unit
shows as failed. That includes a login 1Password would not hand over that day
(it was not looked for) and a broker journal that could not be read to its
end. A run that systemd has to kill (for its time or its memory limit) shows
as failed too, and a second unit, `credbroker-leakcheck-failed.service`, then
sends an alert with a fixed text. Two cases are not covered (see "Known
limits" in `SECURITY.md`): a leak whose alert could not be sent does not show
as failed, and a failed run whose alerts could not be sent shows only here:

```sh
systemctl status credbroker-leakcheck          # the last run
journalctl -u credbroker-leakcheck -n 20
```

To see it work, plant a fake secret: set `canary_file` under `[leakcheck]` in
the config, then run `sudo credbroker-leakcheck --canary`. Your phone gets an
alert labelled "TEST canary", and the app's Alerts list shows where it was
found.

If it finds something real: change that password, then find out how it got there.
Set `[leakcheck] roots` in the config to cover wherever your agents keep
transcripts and notes. Keep any wildcard above the agents' own folders, as in
`/home/*/.claude`: the check's time is shared between the places `roots`
matches, so a wildcard below a folder an agent can write lets that agent add
places and shorten the others' share. With `[mqtt]` configured it also publishes an event.

## When something doesn't work

- **`credbroker: no access to /run/credbroker/broker.sock`:** the user isn't in
  `credbroker-clients`, or its session hasn't restarted since it was added.
- **`unknown_caller`:** the user has no `[agents.<user>]` table in the config.
- **`the browser's port is not protected by the port guard`:** the guard is
  not loaded, or has no line for this agent. Run `sudo vouch-cdp-guard load`
  and read what it says; `sudo browser/setup USER:PORT` adds a missing agent.
- **`the browser is not reachable`, or `chrome-start` says the port is held by
  another user:** the broker types only into a browser whose port the agent's
  own unix user is listening on. Something else is listening on that agent's port; stop it
  and run `chrome-start` as the agent.
- **The broker won't start:** `journalctl -u credbroker`. Without Vouch's
  `vouch-broker` group it stays stopped: install Vouch, then run the broker
  installer again.
- **`no_login`:** no Login item in the agent's vault has a website matching
  the page. **`site_mismatch`:** the page is not the site the login is for.
- **`fill_failed`:** the page is unusual; the agent should use assisted
  sign-in.
- **Nothing on the phone:** check Vouch on its own first:
  `vouch send-test-request` should reach the phone.
- **`timeout`:** the request waited five minutes without an answer.

What the broker protects, and what it doesn't, is in
[SECURITY.md](../SECURITY.md).
