"""Assisted fill: the agent drives the page, the broker only types the secrets.

After approval the agent gets a short-lived handle tied to its tab and login. It
navigates the page itself and, for each secret, points at an input with a CSS
selector; the broker checks the field and the tab's live URL, then types. The
agent never receives a value back.
"""
from __future__ import annotations

import asyncio
import json
import re
import secrets
import time
from dataclasses import dataclass, field

from .cdp import BrowserError, Session, Tab
from .fill import _call, _type
from .match import NoMatch
from .onepw import Credentials, Login

ASSIST_TTL = 180
MAX_FILLS = 10

# Which inputs each secret may go into. The password never goes into a field that
# would show it as plain text.
ALLOWED_TYPES = {
    "username": {"text", "email", "tel"},
    "password": {"password"},
    "answer": {"password", "text"},
}


class FieldRefused(Exception):
    pass


def _word(said: str) -> str:
    """A tag or type as the page gave it, for a reply. The page can make an element say
    anything, and the reply goes to the agent, so only a plain short name is repeated."""
    said = said.lower()
    return said if re.fullmatch(r"[a-z0-9-]{1,32}", said) else "something else"


@dataclass
class Handle:
    id: str
    agent: str
    request_id: str
    tab: Tab
    login: Login
    creds: Credentials = field(repr=False)
    outcome: dict
    started: float
    fills: int = 0
    timer: asyncio.TimerHandle | None = None


class Assisted:
    def __init__(self, ttl: float = ASSIST_TTL):
        self._ttl = ttl
        self._handles: dict[str, Handle] = {}

    def open(self, agent: str, request_id: str, tab: Tab, login: Login, creds: Credentials,
             outcome: dict, on_expire) -> Handle:
        h = Handle(secrets.token_hex(16), agent, request_id, tab, login, creds, outcome, time.monotonic())

        def expire():
            if self._handles.get(h.id) is h:
                on_expire(h.request_id, {**self.close(h), "result": "assisted_expired"})
        h.timer = asyncio.get_running_loop().call_later(self._ttl, expire)
        self._handles[h.id] = h
        return h

    def get(self, handle_id, agent: str) -> Handle | None:
        h = self._handles.get(handle_id) if isinstance(handle_id, str) else None
        if h is None or h.agent != agent or h.fills >= MAX_FILLS:
            return None
        return h

    def close(self, h: Handle) -> dict:
        """Forget the handle (and its credentials); returns the request outcome to record."""
        self._handles.pop(h.id, None)
        if h.timer:
            h.timer.cancel()
        return {**h.outcome, "fill_ms": round((time.monotonic() - h.started) * 1000)}


# Looks through open shadow roots too (custom-element inputs, as some large sites use), in document order.
# The light DOM goes first so an invalid selector still throws.
DEEP_QUERY = """(() => {
  const sel = %s;
  const hit = document.querySelector(sel);
  if (hit) return hit;
  const walk = root => {
    for (const el of root.querySelectorAll('*')) {
      if (!el.shadowRoot) continue;
      const found = el.shadowRoot.querySelector(sel) || walk(el.shadowRoot);
      if (found) return found;
    }
    return null;
  };
  return walk(document);
})()"""


async def type_into(s: Session, selector: str, value: str, kind: str, check) -> None:
    if not check(await s.url()):
        raise NoMatch("site_mismatch")
    try:
        r = await s.send("Runtime.evaluate", {"expression": DEEP_QUERY % json.dumps(selector),
                                              "returnByValue": False})
    except BrowserError:
        raise FieldRefused("could not look up that selector") from None
    if r.get("exceptionDetails"):
        raise FieldRefused("not a valid CSS selector")
    oid = r["result"].get("objectId")
    if not oid:
        raise FieldRefused("no element matches that selector")
    info = await _call(s, oid, """function() {
        const r = this.getBoundingClientRect(), st = getComputedStyle(this);
        return {tag: this.tagName, type: (this.type || '').toLowerCase(), disabled: !!this.disabled,
                readOnly: !!this.readOnly,
                visible: r.width > 0 && r.height > 0 && st.visibility !== 'hidden' && st.display !== 'none'};
    }""")
    if not isinstance(info, dict) or not all(isinstance(info.get(k), str) for k in ("tag", "type")):
        raise FieldRefused("the page would not describe that element")
    if info["tag"] != "INPUT":
        raise FieldRefused(f"that selector matches a {_word(info['tag'])}, not an input")
    if info["type"] not in ALLOWED_TYPES[kind]:
        raise FieldRefused(f"the {kind} only goes into a {' or '.join(sorted(ALLOWED_TYPES[kind]))} input,"
                           f" and this one is type {_word(info['type'] or 'text')}")
    if not info["visible"] or info["disabled"] or info["readOnly"]:
        raise FieldRefused("that input is hidden, disabled or read-only")
    await _type(s, oid, value, check)
