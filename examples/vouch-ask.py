#!/usr/bin/env python3
"""Ask Vouch for approval and wait for the answer. Standard library only.

    vouch-ask --agent "Research agent" --site example.com [--login "Example"]
              [--socket /run/vouch/broker.sock] [--ttl 120]

Exit status: 0 approved (once or always), 1 denied, 2 timed out or cancelled,
3 error. Prints the final state as JSON. Run it as root, or as a user in the
socket's group (vouch-broker by default). Whoever runs it chooses what the
owner's phone shows, so do not put an agent's own user in that group. The API
is described in api/broker.yaml.
"""
from __future__ import annotations

import argparse
import http.client
import json
import secrets
import socket
import sys
from datetime import datetime, timedelta, timezone


class UnixHTTPConnection(http.client.HTTPConnection):
    def __init__(self, path: str, timeout: float):
        super().__init__("vouch", timeout=timeout)
        self._path = path

    def connect(self) -> None:
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(self.timeout)
        self.sock.connect(self._path)


def call(path: str, method: str, url: str, body: dict | None = None, timeout: float = 40) -> tuple[int, dict]:
    conn = UnixHTTPConnection(path, timeout)
    try:
        data = json.dumps(body).encode() if body is not None else None
        conn.request(method, url, body=data, headers={"content-type": "application/json"} if data else {})
        res = conn.getresponse()
        raw = res.read()
        return res.status, json.loads(raw) if raw else {}
    finally:
        conn.close()


def main() -> int:
    p = argparse.ArgumentParser(description="Ask Vouch for approval and wait for the answer.")
    p.add_argument("--agent", required=True, help="who is asking, shown on the phone")
    p.add_argument("--site", required=True, help="the host the login is for, shown on the phone")
    p.add_argument("--login", default=None, help="the login's name in your password manager (never a password)")
    p.add_argument("--socket", default="/run/vouch/broker.sock")
    p.add_argument("--ttl", type=int, default=120, help="seconds to wait for an answer, at most 3600")
    a = p.parse_args()

    request_id = f"req_{secrets.token_urlsafe(12)}"
    expires = datetime.now(timezone.utc) + timedelta(seconds=max(10, min(a.ttl, 3600)))
    body = {"request_id": request_id, "kind": "sign_in", "agent": a.agent, "site": a.site,
            "login_title": a.login, "expires_at": expires.isoformat().replace("+00:00", "Z")}
    try:
        status, r = call(a.socket, "POST", "/v1/approvals", body)
        if status != 202:
            print(json.dumps(r), file=sys.stderr)
            return 3
        # Long-poll in 30 s steps until the owner answers or the request expires.
        while r.get("state") == "pending":
            status, r = call(a.socket, "GET", f"/v1/approvals/{request_id}?wait=30")
            if status != 200:
                print(json.dumps(r), file=sys.stderr)
                return 3
    except KeyboardInterrupt:
        call(a.socket, "POST", f"/v1/approvals/{request_id}/cancel")
        return 2
    except OSError as e:
        print(f"vouch-ask: can't reach {a.socket}: {e.strerror or e}", file=sys.stderr)
        return 3
    print(json.dumps(r))
    return {"once": 0, "always": 0, "deny": 1}.get(r["state"], 2)


if __name__ == "__main__":
    sys.exit(main())
