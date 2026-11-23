"""What the broker believes about an agent's DevTools port.

The port guard lets the broker's uid through to every agent's port and does not decide who
listens on one. So the broker must check that the port is served by the agent it is acting
for, and must not let the port send it anywhere else.
"""
import asyncio
import http
import http.server
import json
import os
import threading

import pytest
import websockets
from conftest import not_as_root

from credbroker import cdp, config
from credbroker.approval import Decision
from credbroker.config import Agent
from credbroker.onepw import Credentials, Login, Website
from credbroker.server import Broker
from credbroker.store import Store

B_TAB = "https://bank.example.org/accounts"
ME = os.getuid()         # every listener in these tests belongs to this user
SOMEONE_ELSE = ME + 1


class Victim:
    """Agent B's DevTools endpoint: records every request the broker makes to it."""

    def __init__(self):
        self.http_hits, self.ws_hits, self.port = [], [], None

    def http(self, connection, request):
        if request.headers.get("Upgrade"):
            return None
        self.http_hits.append(request.path)
        body = json.dumps([{"id": "b1", "type": "page", "url": B_TAB,
                            "webSocketDebuggerUrl": f"ws://127.0.0.1:{self.port}/devtools/page/b1"}])
        return connection.respond(http.HTTPStatus.OK, body)

    async def ws(self, ws):
        self.ws_hits.append(ws.request.path)
        async for raw in ws:
            m = json.loads(raw)
            await ws.send(json.dumps({"id": m["id"], "result": {"result": {"value": B_TAB}}}))


def attacker_port(handler_body):
    """Agent A's port: a plain HTTP server whose GET is `handler_body(self)`."""
    class H(http.server.BaseHTTPRequestHandler):
        do_GET = handler_body

        def log_message(self, *a):
            pass
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv


def redirect_to(victim):
    def get(self):
        self.send_response(302)
        self.send_header("Location", f"http://127.0.0.1:{victim.port}{self.path}")
        self.end_headers()
    return get


def test_list_tabs_does_not_follow_a_redirect_to_another_port():
    victim = Victim()

    async def go():
        async with websockets.serve(victim.ws, "127.0.0.1", 0, process_request=victim.http) as srv:
            victim.port = srv.sockets[0].getsockname()[1]
            a = attacker_port(redirect_to(victim))
            try:
                return await cdp.list_tabs(a.server_address[1], ME)
            except cdp.BrowserError:
                return []
            finally:
                a.shutdown()
    tabs = asyncio.run(go())
    assert victim.http_hits == [], f"the broker fetched {victim.http_hits} from another agent's port"
    assert tabs == []


def test_session_does_not_connect_to_a_websocket_url_on_another_port():
    victim = Victim()

    def get(self):
        body = json.dumps([{"id": "x", "type": "page", "url": "https://portal.example.com/login",
                            "webSocketDebuggerUrl": f"ws://127.0.0.1:{victim.port}/devtools/page/b1"}]).encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    async def go():
        async with websockets.serve(victim.ws, "127.0.0.1", 0, process_request=victim.http) as srv:
            victim.port = srv.sockets[0].getsockname()[1]
            a = attacker_port(get)
            try:
                tab = await cdp.find_tab(a.server_address[1], "https://portal.example.com/login", ME)
                async with cdp.Session(tab) as s:
                    return await s.url()
            except cdp.BrowserError:
                return None
            finally:
                a.shutdown()
    seen = asyncio.run(go())
    assert victim.ws_hits == [], f"the broker opened {victim.ws_hits} on another agent's port and read {seen!r} there"


class Vault:
    async def logins(self, fresh=False):
        return [Login("l1", "Example", (Website("https://portal.example.com", "AnywhereOnWebsite"),))]

    async def credentials(self, login_id):
        return Credentials("alex@example.com", "correct horse")


class Approvals:
    async def ask(self, prompt):
        return Decision("deny", 1, 1)


def test_sign_in_replies_do_not_reveal_another_agents_open_tabs(tmp_path):
    """A asks to sign in on a guessed URL; the reply differs when B has that URL open."""
    victim = Victim()

    async def go():
        async with websockets.serve(victim.ws, "127.0.0.1", 0, process_request=victim.http) as srv:
            victim.port = srv.sockets[0].getsockname()[1]
            a = attacker_port(redirect_to(victim))
            agent = Agent("research", ME, cdp_port=a.server_address[1])
            b = Broker({ME: agent}, {"research": Vault()}, Store(tmp_path / "b.db"), Approvals())
            try:
                right = await b.sign_in(agent, {"url": B_TAB, "reason": "guess"})
                wrong = await b.sign_in(agent, {"url": "https://bank.example.org/other", "reason": "guess"})
            finally:
                a.shutdown()
            return right, wrong
    right, wrong = asyncio.run(go())
    print("B has it open:", right, "\nB does not:   ", wrong)
    assert right == wrong, "the two replies tell agent A which URL agent B has open"


class Squatter:
    """A DevTools endpoint on the agent's port that another unix user started."""

    def __init__(self, replies=None):
        self.http_hits, self.messages, self.port, self.replies = [], [], None, replies or {}

    def http(self, connection, request):
        if request.headers.get("Upgrade"):
            return None
        self.http_hits.append(request.path)
        body = json.dumps([{"id": "p1", "type": "page", "url": "https://portal.example.com/login"}])
        return connection.respond(http.HTTPStatus.OK, body)

    async def ws(self, ws):
        async for raw in ws:
            m = json.loads(raw)
            self.messages.append(m)
            result = self.replies.get(m["method"], {"result": {"value": "https://portal.example.com/login"}})
            await ws.send(json.dumps({"id": m["id"], "result": result}))

    def serve(self):
        return websockets.serve(self.ws, "127.0.0.1", 0, process_request=self.http)


@not_as_root
def test_list_tabs_asks_nothing_of_a_port_served_by_another_user():
    sq = Squatter()

    async def go():
        async with sq.serve() as srv:
            port = srv.sockets[0].getsockname()[1]
            assert [t.id for t in await cdp.list_tabs(port, ME)] == ["p1"]  # the owner's own port works
            sq.http_hits.clear()
            with pytest.raises(cdp.BrowserError) as e:
                await cdp.list_tabs(port, SOMEONE_ELSE)
            return e.value.code
    assert asyncio.run(go()) == "browser_unavailable"
    assert sq.http_hits == []


def test_session_sends_nothing_to_a_port_served_by_another_user():
    sq = Squatter()

    async def go():
        async with sq.serve() as srv:
            port = srv.sockets[0].getsockname()[1]
            tab = cdp.Tab("p1", "https://portal.example.com/login", f"ws://127.0.0.1:{port}/devtools/page/p1", SOMEONE_ELSE)
            with pytest.raises(cdp.BrowserError) as e:
                async with cdp.Session(tab) as s:
                    await s.url()
            return e.value.code
    assert asyncio.run(go()) == "browser_unavailable"
    assert sq.messages == []


class Yes:
    async def ask(self, prompt):
        return Decision("once", 1, 1)


def test_sign_in_types_nothing_into_a_browser_another_user_started(tmp_path):
    """Agent A's Chrome is down and agent B listens on A's port: A's password must not go there."""
    sq = Squatter()

    async def go():
        async with sq.serve() as srv:
            agent = Agent("research", SOMEONE_ELSE, cdp_port=srv.sockets[0].getsockname()[1])
            b = Broker({agent.uid: agent}, {"research": Vault()}, Store(tmp_path / "b.db"), Yes())
            return await b.sign_in(agent, {"url": "https://portal.example.com/login", "reason": "r"})
    r = asyncio.run(go())
    assert r["result"] == "fill_failed" and r["reason"] == "the browser is not reachable"
    assert sq.http_hits == [] and sq.messages == []
    assert "correct horse" not in json.dumps(sq.messages)


def test_a_malformed_reply_from_the_port_is_a_failed_fill_not_a_crash(tmp_path):
    sq = Squatter(replies={"Runtime.evaluate": {"unexpected": True}})

    async def go():
        async with sq.serve() as srv:
            agent = Agent("research", ME, cdp_port=srv.sockets[0].getsockname()[1])
            b = Broker({ME: agent}, {"research": Vault()}, Store(tmp_path / "b.db"), Yes())
            return await b.sign_in(agent, {"url": "https://portal.example.com/login", "reason": "r"})
    r = asyncio.run(go())
    assert r["result"] == "fill_failed"


@not_as_root
def test_sign_in_types_nothing_into_a_port_the_guard_does_not_cover(tmp_path, monkeypatch):
    """The agent is in the broker's config but the guard never loaded, or has no line for it."""
    sq = Squatter()
    state = tmp_path / "guarded"
    monkeypatch.setattr(config, "GUARD_STATE", str(state))

    async def go(port_line):
        async with sq.serve() as srv:
            port = srv.sockets[0].getsockname()[1]
            if port_line:
                state.write_text(port_line.format(port=port, me=ME))
            agent = Agent("research", ME, cdp_port=port)
            b = Broker({ME: agent}, {"research": Vault()}, Store(tmp_path / f"{len(port_line)}.db"), Yes())
            return await b.sign_in(agent, {"url": "https://portal.example.com/login", "reason": "r"})
    for line in ("", "{port} 1\n", "1 {me}\n"):   # no record; the port for another user; another port
        r = asyncio.run(go(line))
        assert r["result"] == "fill_failed" and "port guard" in r["reason"]
    assert sq.http_hits == [] and sq.messages == []
    r = asyncio.run(go("{port} {me}\n"))
    assert "port guard" not in (r.get("reason") or "") and sq.http_hits   # covered: the broker goes ahead


def test_session_does_not_follow_a_redirect_on_the_websocket_upgrade():
    """The agent's port answers the upgrade with a redirect. The
    broker must not go where it points, on this machine or anywhere else."""
    victim = Victim()

    async def go():
        async with websockets.serve(victim.ws, "127.0.0.1", 0, process_request=victim.http) as srv:
            victim.port = srv.sockets[0].getsockname()[1]

            async def redirect(reader, writer):
                await reader.readuntil(b"\r\n\r\n")
                writer.write(f"HTTP/1.1 302 Found\r\nLocation: ws://127.0.0.1:{victim.port}/devtools/page/b1\r\n"
                             "Content-Length: 0\r\n\r\n".encode())
                await writer.drain()
                writer.close()
            a = await asyncio.start_server(redirect, "127.0.0.1", 0)
            tab = cdp.Tab("x", "https://portal.example.com/login",
                          f"ws://127.0.0.1:{a.sockets[0].getsockname()[1]}/devtools/page/x", ME)
            async with a:
                try:
                    async with cdp.Session(tab) as s:
                        return await s.url()
                except cdp.BrowserError as e:
                    return e
    seen = asyncio.run(go())
    assert victim.ws_hits == [], f"the broker followed the redirect to {victim.ws_hits} and read {seen!r} there"
    assert isinstance(seen, cdp.BrowserError) and seen.code == "browser_unavailable"


def test_session_sends_no_handshake_to_a_port_served_by_another_user():
    """The owner of the port is checked on the bare connection, before a byte is sent."""
    got = []

    async def listener(reader, writer):
        got.append(await reader.read(4096))
        writer.close()

    async def go():
        srv = await asyncio.start_server(listener, "127.0.0.1", 0)
        async with srv:
            port = srv.sockets[0].getsockname()[1]
            tab = cdp.Tab("p1", "https://portal.example.com/login", f"ws://127.0.0.1:{port}/devtools/page/p1", SOMEONE_ELSE)
            with pytest.raises(cdp.BrowserError) as e:
                async with cdp.Session(tab):
                    pass
            await asyncio.sleep(0.2)
            return e.value.code
    assert asyncio.run(go()) == "browser_unavailable"
    assert got in ([], [b""]), f"the broker sent {got!r} to a port another user serves"


@not_as_root
def test_session_does_not_use_a_proxy_from_the_environment(monkeypatch):
    """A proxy setting must not carry a loopback DevTools connection off the machine."""
    proxied = []

    async def proxy(reader, writer):
        proxied.append(await reader.read(4096))
        writer.close()
    sq = Squatter()

    async def go():
        p = await asyncio.start_server(proxy, "127.0.0.1", 0)
        async with p, sq.serve() as srv:
            for var in ("ws_proxy", "http_proxy", "all_proxy", "WS_PROXY", "HTTP_PROXY", "ALL_PROXY"):
                monkeypatch.setenv(var, f"http://127.0.0.1:{p.sockets[0].getsockname()[1]}")
            for var in ("no_proxy", "NO_PROXY"):
                monkeypatch.delenv(var, raising=False)
            port = srv.sockets[0].getsockname()[1]
            tab = cdp.Tab("p1", "https://portal.example.com/login", f"ws://127.0.0.1:{port}/devtools/page/p1", ME)
            try:
                async with cdp.Session(tab) as s:
                    return await s.url()
            except cdp.BrowserError as e:
                return e
    seen = asyncio.run(go())
    assert proxied == [], "the broker sent its DevTools connection through a proxy"
    assert seen == "https://portal.example.com/login"
