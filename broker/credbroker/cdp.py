"""The agent's own Chrome, over the DevTools protocol.

The browser is shared with the agent and holds the owner's live sessions: this module
never closes the browser or any tab, and never opens one.
"""
from __future__ import annotations

import asyncio
import http.client
import itertools
import json
import re
import socket
import time
from dataclasses import dataclass
from urllib.parse import urldefrag, urlsplit

import websockets


class BrowserError(Exception):
    def __init__(self, code: str, detail: str = ""):
        super().__init__(f"{code}: {detail}" if detail else code)
        self.code = code  # browser_unavailable | tab_not_found | cdp_error


@dataclass(frozen=True)
class Tab:
    id: str
    url: str
    ws_url: str
    owner: int | None = None  # the unix user whose browser this must be


_TARGET_ID = re.compile(r"[A-Za-z0-9_-]{1,64}")
_LOOPBACK = "0100007F"  # 127.0.0.1 as /proc/net/tcp prints it


def guarded(port: int, owner: int, state: str) -> bool:
    """Whether the port guard has recorded that it restricts `port` to unix user `owner`.

    A DevTools port has no login. Without the guard, any user on the machine can drive the
    browser on it, so nothing is typed into a port the guard is not known to cover.
    """
    if not state:
        return True
    try:
        with open(state) as f:
            return f"{port} {owner}" in {line.strip() for line in f}
    except OSError:
        return False


def _served_by(sock, owner: int, wait: float = 3) -> bool:
    """Whether the far end of this loopback connection is a socket of unix user `owner`.

    The port guard decides who may connect to an agent's port, not who listens on it, so
    another user can take the port while the agent's Chrome is down. The kernel's socket
    table names the owner of the socket that accepted this very connection. Until the far
    end has accepted it, the kernel reports owner 0, so that is waited out, never believed.
    """
    if owner == 0:
        return False
    ours, theirs = (f"{_LOOPBACK}:{p:04X}" for p in (sock.getsockname()[1], sock.getpeername()[1]))
    deadline = time.monotonic() + wait
    while True:
        try:
            with open("/proc/net/tcp") as f:
                uids = {row[7] for row in map(str.split, f) if len(row) > 7 and row[1] == theirs and row[2] == ours}
        except OSError:
            return False
        if uids != {"0"} or time.monotonic() > deadline:
            return uids == {str(owner)}
        time.sleep(0.02)


def _get_tabs(port: int, owner: int):
    # http.client does not follow redirects: the port answers for itself or not at all.
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
    try:
        conn.connect()
        if not _served_by(conn.sock, owner):
            raise BrowserError("browser_unavailable", "port not served by the agent")
        conn.request("GET", "/json/list")
        r = conn.getresponse()
        if r.status != 200:
            raise ValueError(r.status)
        return json.load(r)
    finally:
        conn.close()


async def list_tabs(port: int, owner: int) -> list[Tab]:
    """The pages open in the browser on `port`, which must belong to unix user `owner`."""
    try:
        targets = await asyncio.to_thread(_get_tabs, port, owner)
        # The address is built here: what the port says its websocket address is, is not believed.
        return [Tab(t["id"], t["url"], f"ws://127.0.0.1:{port}/devtools/page/{t['id']}", owner)
                for t in targets
                if t.get("type") == "page" and isinstance(t["url"], str) and _TARGET_ID.fullmatch(t["id"])]
    except (OSError, ValueError, KeyError, TypeError, AttributeError, RecursionError, http.client.HTTPException) as e:
        raise BrowserError("browser_unavailable", type(e).__name__) from None


def _norm(url: str) -> str:
    return urldefrag(url)[0].rstrip("/")


def pick(tabs: list[Tab], url: str) -> Tab:
    """The tab showing `url`; failing an exact match, ignore the fragment and a trailing slash."""
    for same in (lambda t: t.url == url, lambda t: _norm(t.url) == _norm(url)):
        hits = [t for t in tabs if same(t)]
        if hits:
            return hits[0]  # /json/list is most recently used first
    raise BrowserError("tab_not_found")


async def find_tab(port: int, url: str, owner: int) -> Tab:
    return pick(await list_tabs(port, owner), url)


class Session:
    """One CDP connection to one tab. Closing it detaches; the tab stays open."""

    def __init__(self, tab: Tab):
        self.tab = tab
        self._ws = None
        self._ids = itertools.count(1)

    async def __aenter__(self) -> Session:
        # The connection is made here and its far end checked before a byte is sent. Handing
        # the library a connected socket also stops it following a redirect from the port,
        # and no proxy from the environment is used: this is loopback or nothing.
        u = urlsplit(self.tab.ws_url)
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.setblocking(False)
        try:
            async with asyncio.timeout(5):
                await asyncio.get_running_loop().sock_connect(sock, ("127.0.0.1", u.port))
            if self.tab.owner is not None and not await asyncio.to_thread(_served_by, sock, self.tab.owner):
                raise BrowserError("browser_unavailable", "port not served by the agent")
            # ValueError is how the library refuses a redirect when it was given the socket.
            self._ws = await websockets.connect(self.tab.ws_url, sock=sock, proxy=None,
                                                max_size=16 * 2**20, open_timeout=5)
        except (OSError, ValueError, TypeError, websockets.WebSocketException) as e:
            sock.close()
            raise BrowserError("browser_unavailable", type(e).__name__) from None
        except BaseException:
            sock.close()
            raise
        return self

    async def __aexit__(self, *exc) -> None:
        await self._ws.close()

    async def send(self, method: str, params: dict | None = None, timeout: float = 15) -> dict:
        msg_id = next(self._ids)
        await self._ws.send(json.dumps({"id": msg_id, "method": method, "params": params or {}}))
        async with asyncio.timeout(timeout):
            async for raw in self._ws:
                msg = json.loads(raw)
                if msg.get("id") == msg_id:
                    if "error" in msg:
                        raise BrowserError("cdp_error", f"{method}: {msg['error'].get('message')}")
                    return msg.get("result", {})
        raise BrowserError("cdp_error", f"{method}: connection closed")

    async def url(self) -> str:
        """Where the tab is right now, which may have moved since it was found."""
        r = await self.send("Runtime.evaluate", {"expression": "location.href", "returnByValue": True})
        try:
            return r["result"]["value"]
        except (KeyError, TypeError):
            raise BrowserError("cdp_error", "malformed reply") from None
