# Connecting your agent

Agents talk to Vouch through Unix sockets on the Vouch server. Nothing here is
reachable over the network, and there are no API keys: whether a process may
connect is decided by the socket's file permissions, so you grant access by
adding a user to a group. Only `vouch-sms` is for an agent's own user.
`vouch-broker` is for a broker that asks on the agent's behalf (see below).

| Socket | Group | What it's for |
|---|---|---|
| `/run/vouch/broker.sock` | `vouch-broker` | For a broker, never the agent itself: ask the owner to approve a sign-in, and wait for the answer. |
| `/run/vouch/sms.sock` | `vouch-sms` | Text from the agent's own number (only with the SMS module on). |

Add a user to a group with `sudo usermod -aG <group> <user>`; the process sees
the group after it restarts. With Docker, see `server/deploy/docker/README.md`.

Be careful who goes in `vouch-broker`. Vouch shows the owner whatever a member
of that group sends: the agent name, the site, the login title, and alerts. It
has no way to check them. Put there a broker you trust to fill those in
honestly, running as its own user, and keep the agent's user out. An agent
that can open this socket itself can show the owner a request that says
anything. The credential broker in [broker.md](broker.md) is such a broker:
it takes the agent from the kernel, the site from the browser and the title
from 1Password.

## Approvals: broker.sock

HTTP with JSON over the socket. The full contract is
[`api/broker.yaml`](../api/broker.yaml). In short:

1. `POST /v1/approvals` with your own `request_id`, `kind: "sign_in"`, the
   `agent` and `site` to show, and `expires_at` (at most an hour ahead). Vouch
   pushes it to the owner's phones and answers `202`.
2. `GET /v1/approvals/{request_id}?wait=30` until `state` leaves `pending`.
3. `once` or `always` means go ahead (`always` means the owner allowed this
   login from now on); `deny`, `timeout` or `cancelled` means don't.
4. Changed your mind? `POST /v1/approvals/{request_id}/cancel`.

Creating the same request twice is safe, so retry freely after a dropped
connection.

The owner reads `agent`, `site` and `login_title` on the phone, so Vouch
answers `400` unless `site` is a host name or an IP address, and unless the
other two are one line of visible text: no control characters, line breaks, or
invisible or direction-changing characters.

```sh
curl --unix-socket /run/vouch/broker.sock -H 'content-type: application/json' \
  -d '{"request_id":"req_0123456789","kind":"sign_in","agent":"Research agent",
       "site":"example.com","expires_at":"2026-11-15T21:00:00Z"}' \
  http://vouch/v1/approvals
curl --unix-socket /run/vouch/broker.sock 'http://vouch/v1/approvals/req_0123456789?wait=30'
```

### Example client

[`examples/vouch-ask.py`](../examples/vouch-ask.py) is a one-file Python client
(standard library only) that asks and waits:

```sh
examples/vouch-ask.py --agent "Research agent" --site example.com && echo approved
```

It exits 0 when approved, 1 when denied, 2 on timeout or cancel and 3 on error,
which makes it easy to put in front of any script or agent tool.

The credential broker in [`broker/`](../broker) is the full-size client of
this socket: it asks for approval the same way
([`credbroker/approval.py`](../broker/credbroker/approval.py)), then signs the
agent in with a login from 1Password. Use it as it is
([guide](broker.md)), or read it as a reference for your own.

## SMS: sms.sock

Newline-delimited JSON: write one request per line, read one reply per line,
in order. Every request carries an `id` you choose, echoed in the reply.

```
→ {"id": 1, "op": "send", "to": "+12045550150", "text": "Running late"}
← {"id": 1, "ok": true, "result": {"sent": true, "to": "+12045550150", "text": "...", "message_id": "msg_..."}}
← {"id": 2, "ok": false, "error": {"code": "not_approved", "message": "..."}}
```

| `op` | Fields | Result |
|---|---|---|
| `send` | `to`, `text` | `{sent, to, text, message_id}`. The text may gain the intro line. |
| `request_approval` | `phone`, `name`, `reason` | `{pending, phone, request_id, note}`, or `{already_approved}`. The owner approves in the app; the outcome arrives on the agent's MQTT inbox. |
| `contacts` | none | `{owner, contacts, pending}` |
| `history` | `phone` (optional), `limit` (1 to 200, default 20) | `{messages}`, oldest first |
| `status` | none | provider, whether incoming texts are connected, sends in the last 24 hours against the caps |

Refusal codes: `invalid`, `not_approved`, `daily_cap`, `provider`,
`too_many_pending`, `not_available`, `bad_request`. Texts that arrive for the
agent are relayed to the MQTT topic set in `[sms.mqtt] agent_inbox`.
