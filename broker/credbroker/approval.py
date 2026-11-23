"""The owner's answer to a sign-in prompt, through Vouch.

Vouch (server/ in this repository) owns the phone side: it pushes the request
to every paired phone and records the first signed decision. The broker only
creates the request on Vouch's unix socket and long-polls it. The answer is
once, always, deny or timeout.
"""
from __future__ import annotations

import asyncio
import http.client
import json
import logging
import socket
import time
import unicodedata
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

log = logging.getLogger("credbroker")

TIMEOUT_S = 300
WAIT_S = 30  # Vouch's longest single long poll
MAX_TITLE = 200  # the longest login title Vouch accepts
STATES = {"once", "always", "deny", "timeout"}
_HIDDEN = {"Cc", "Cf", "Cs", "Cn", "Zl", "Zp"}  # the Unicode categories Vouch refuses in text it shows
# Letters and symbols that are drawn as nothing, which Vouch refuses too: the Hangul fillers, the blank
# Braille pattern, the null notehead and the object replacement character.
_BLANK = "\u115f\u1160\u2800\u3164\uffa0\U0001d159\ufffc"


class ApprovalError(Exception):
    pass


@dataclass(frozen=True)
class Prompt:
    request_id: str
    agent: str
    site: str
    username: str
    reason: str
    login_title: str | None = None


@dataclass(frozen=True)
class Decision:
    decision: str  # once | always | deny | timeout
    notify_ms: int
    decide_ms: int


class _UnixHTTP(http.client.HTTPConnection):
    def __init__(self, path: str, timeout: float):
        super().__init__("approver", timeout=timeout)  # the Host header Vouch has always been sent
        self._path = path

    def connect(self) -> None:
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(self.timeout)
        self.sock.connect(self._path)


class VouchApprovals:
    def __init__(self, path: str, timeout: float = TIMEOUT_S):
        self._path = path
        self._timeout = timeout

    def _call(self, method: str, target: str, body: dict | None = None) -> tuple[int, dict]:
        conn = _UnixHTTP(self._path, timeout=WAIT_S + 10)
        try:
            conn.request(method, target, body=json.dumps(body) if body is not None else None,
                         headers={"Content-Type": "application/json"} if body is not None else {})
            r = conn.getresponse()
            raw = r.read()
            return r.status, json.loads(raw) if raw else {}
        except (OSError, http.client.HTTPException, ValueError) as e:
            raise ApprovalError(f"Vouch at {self._path}: {type(e).__name__}") from None
        finally:
            conn.close()

    @staticmethod
    def _plain(text: str, keep: str = "") -> str:
        """Vouch refuses text with control or invisible characters in it. Some of what is sent
        comes from an agent (a file name the leak check found), which must not get the alert refused."""
        return "".join("?" if c not in keep and (unicodedata.category(c) in _HIDDEN or c in _BLANK) else c
                       for c in text)

    def alert(self, alert_id: str, severity: str, title: str, body: str) -> None:
        """Tell the owner's phones about a problem. Never pass a secret in `title` or `body`."""
        status, resp = self._call("POST", "/v1/alerts", {
            "alert_id": alert_id, "severity": severity, "title": self._plain(title)[:120], "body": self._plain(body, keep="\n")[:2000]})
        if status != 202:
            raise ApprovalError(f"Vouch refused the alert: HTTP {status} {resp.get('code', '')}")

    async def ask(self, prompt: Prompt) -> Decision:
        expires = datetime.now(UTC) + timedelta(seconds=self._timeout)
        t = time.monotonic()
        status, body = await asyncio.to_thread(self._call, "POST", "/v1/approvals", {
            "request_id": prompt.request_id, "kind": "sign_in", "agent": prompt.agent.capitalize(),
            "site": prompt.site, "login_title": self._plain(prompt.login_title or "")[:MAX_TITLE].strip() or None,
            "expires_at": expires.isoformat(timespec="milliseconds").replace("+00:00", "Z")})
        if status != 202:
            raise ApprovalError(f"Vouch refused the request: HTTP {status} {body.get('code', '')}")
        notify_ms = round((time.monotonic() - t) * 1000)
        t = time.monotonic()
        try:
            state = body.get("state")
            while state == "pending":
                status, body = await asyncio.to_thread(
                    self._call, "GET", f"/v1/approvals/{prompt.request_id}?wait={WAIT_S}")
                if status != 200:
                    raise ApprovalError(f"Vouch lost request {prompt.request_id}: HTTP {status}")
                state = body.get("state")
        except asyncio.CancelledError:
            await asyncio.to_thread(self._cancel, prompt.request_id)
            raise
        decide_ms = round((time.monotonic() - t) * 1000)
        if state not in STATES:
            # cancelled by someone else, or a state this broker does not know: never a yes
            log.warning("Vouch ended request %s as %s; treating it as a timeout", prompt.request_id, state)
            state = "timeout"
        return Decision(state, notify_ms, decide_ms)

    def _cancel(self, request_id: str) -> None:
        try:
            self._call("POST", f"/v1/approvals/{request_id}/cancel")
        except ApprovalError as e:
            log.warning("could not cancel %s on Vouch: %s", request_id, e)
