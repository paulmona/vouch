import asyncio
import json
import os
import time

import pytest
from test_fill import CHROME, chrome, open_tab, web  # noqa: F401  (fixtures)

from credbroker import cdp
from credbroker.approval import Decision
from credbroker.assisted import Assisted
from credbroker.config import Agent
from credbroker.onepw import Credentials, Login, Website
from credbroker.server import Broker
from credbroker.store import Store

SECRET = Credentials("alex@example.com", "correct horse", {"Your first car": "Corolla"})


class Vault:
    def __init__(self, site):
        self.login = Login("l1", "Test site", (Website(site, "AnywhereOnWebsite"),))

    async def logins(self, fresh=False):
        return [self.login]

    async def credentials(self, login_id):
        return SECRET


class Approvals:
    def __init__(self, answer="once"):
        self.answer = answer

    async def ask(self, prompt):
        return Decision(self.answer, 100, 1000)


class Bus:
    def __init__(self):
        self.events = []

    def emit(self, row):
        self.events.append(row)


def broker(tmp_path, port, site, answer="once"):
    agent = Agent("research", os.getuid(), cdp_port=port)  # the test's Chrome is this user's
    b = Broker({agent.uid: agent}, {"research": Vault(site)}, Store(tmp_path / "b.db"), Approvals(answer), Bus())
    return b, agent


async def page_js(port, url, expression):
    """What the agent itself does with its own browser: click, navigate, read."""
    tab = await cdp.find_tab(port, url, os.getuid())
    async with cdp.Session(tab) as s:
        r = await s.send("Runtime.evaluate", {"expression": expression, "returnByValue": True, "awaitPromise": True})
        return r["result"].get("value")


needs_chrome = pytest.mark.skipif(not CHROME, reason="needs google-chrome")


@needs_chrome
def test_two_step_assisted(tmp_path, chrome, web):
    url = f"{web}/twostep.html"
    open_tab(chrome, url)
    time.sleep(0.5)
    b, research = broker(tmp_path, chrome, web)

    async def go():
        r = await b.begin_sign_in(research, {"url": url, "reason": "test"})
        assert r["ok"] and r["secrets"] == ["username", "password", "answer"] and r["questions"] == ["Your first car"]
        assert "Sign out of 127.0.0.1" in r["sign_out"]
        h = r["handle"]
        assert await b.fill_field(research, {"handle": h, "selector": "#email", "secret": "username"}) == {"ok": True, "result": "typed"}
        await page_js(chrome, url, "document.getElementById('next').click()")
        refused = await b.fill_field(research, {"handle": h, "selector": "#nick", "secret": "password"})
        assert refused["error"] == "field_refused" and "password" in refused["message"]
        assert (await b.fill_field(research, {"handle": h, "selector": "#pw", "secret": "password"}))["result"] == "typed"
        await page_js(chrome, url, "document.getElementById('go').click()")
        await asyncio.sleep(1)
        assert (await page_js(chrome, f"{web}/home.html", "location.pathname")) == "/home.html"
        assert await b.end_sign_in(research, {"handle": h, "signed_in": True}) == {"ok": True}
        assert (await b.fill_field(research, {"handle": h, "selector": "#pw", "secret": "password"}))["error"] == "no_handle"
        return r
    r = asyncio.run(go())
    (e,) = b.bus.events
    assert e["result"] == "assisted_signed_in" and e["decision"] == "once"
    assert SECRET.password not in json.dumps(r) and SECRET.username not in json.dumps(r)


@needs_chrome
def test_fill_refused_after_tab_leaves_site(tmp_path, chrome, web):
    url = f"{web}/login.html?assist=1"
    open_tab(chrome, url)
    time.sleep(0.5)
    b, research = broker(tmp_path, chrome, web)
    elsewhere = web.replace("127.0.0.1", "localhost") + "/login.html"

    async def go():
        h = (await b.begin_sign_in(research, {"url": url, "reason": "test"}))["handle"]
        await page_js(chrome, url, f"location.href = {json.dumps(elsewhere)}")
        await asyncio.sleep(1)
        r = await b.fill_field(research, {"handle": h, "selector": "#pw", "secret": "password"})
        assert r["error"] == "site_mismatch"
        assert (await b.fill_field(research, {"handle": h, "selector": "#pw", "secret": "password"}))["error"] == "no_handle"
        assert await page_js(chrome, elsewhere, "document.getElementById('pw').value") == ""
    asyncio.run(go())
    assert b.bus.events[0]["result"] == "site_mismatch"


@needs_chrome
def test_bad_selectors_and_answers(tmp_path, chrome, web):
    url = f"{web}/login.html?assist=2"
    open_tab(chrome, url)
    time.sleep(0.5)
    b, research = broker(tmp_path, chrome, web)

    async def go():
        h = (await b.begin_sign_in(research, {"url": url, "reason": "test"}))["handle"]
        f = lambda **kw: b.fill_field(research, {"handle": h, **kw})
        assert (await f(selector="#nope", secret="password"))["message"] == "no element matches that selector"
        assert (await f(selector="))((", secret="password"))["message"] == "not a valid CSS selector"
        assert "not an input" in (await f(selector="button", secret="password"))["message"]
        assert "hidden" in (await f(selector="[name=trap]", secret="password"))["message"]
        assert (await f(selector="#pw", secret="answer", question="Your pet?"))["error"] == "no_answer"
        assert (await f(selector="#pw", secret="token"))["error"] == "bad_request"
    asyncio.run(go())


def test_denied_gets_no_handle(tmp_path, monkeypatch):
    b, research = broker(tmp_path, 9222, "https://x.example", answer="deny")

    async def find_tab(port, url, owner):
        return cdp.Tab("t", "https://x.example/login", "ws://x")
    monkeypatch.setattr(cdp, "find_tab", find_tab)
    r = asyncio.run(b.begin_sign_in(research, {"url": "https://x.example/login", "reason": "r"}))
    assert r == {"ok": False, "result": "denied"} and b.bus.events[0]["result"] == "denied"


def test_code_only_login_offers_username_only(tmp_path, monkeypatch):
    b, research = broker(tmp_path, 9222, "https://x.example")

    async def credentials(login_id):
        return Credentials("alex@example.com", "")
    b.vaults["research"].credentials = credentials

    async def find_tab(port, url, owner):
        return cdp.Tab("t", "https://x.example/login", "ws://x")
    monkeypatch.setattr(cdp, "find_tab", find_tab)

    async def go():
        r = await b.begin_sign_in(research, {"url": "https://x.example/login", "reason": "r"})
        assert r["ok"] and r["secrets"] == ["username"]
        refused = await b.fill_field(research, {"handle": r["handle"], "selector": "#pw", "secret": "password"})
        assert refused["error"] == "no_password"
        assert await b.end_sign_in(research, {"handle": r["handle"], "signed_in": True}) == {"ok": True}
    asyncio.run(go())
    assert b.bus.events[0]["result"] == "assisted_signed_in"


def test_handles_are_per_agent_and_expire():
    expired = []

    async def go():
        a = Assisted(ttl=0.05)
        h = a.open("research", "r1", cdp.Tab("t", "u", "w"), Vault("https://x").login, SECRET, {"decision": "once"},
                   on_expire=lambda rid, out: expired.append((rid, out["result"])))
        assert a.get(h.id, "assistant") is None and a.get(h.id, "research") is h
        await asyncio.sleep(0.1)
        assert a.get(h.id, "research") is None
    asyncio.run(go())
    assert expired == [("r1", "assisted_expired")]


@needs_chrome
def test_fills_inputs_inside_shadow_roots(tmp_path, chrome, web):
    url = f"{web}/shadow.html"
    open_tab(chrome, url)
    time.sleep(0.5)
    b, research = broker(tmp_path, chrome, web)
    length = ("(n => { const f = r => { for (const e of r.querySelectorAll('*')) { if (!e.shadowRoot) continue;"
              " const i = e.shadowRoot.querySelector(`input[name=${n}]`) || f(e.shadowRoot); if (i) return i; } return null; };"
              " return f(document).value.length; })")

    async def go():
        h = (await b.begin_sign_in(research, {"url": url, "reason": "test"}))["handle"]
        f = lambda **kw: b.fill_field(research, {"handle": h, **kw})
        assert (await f(selector="input[name=email]", secret="username"))["result"] == "typed"
        assert (await f(selector="input[name=password]", secret="password"))["result"] == "typed"
        assert await page_js(chrome, url, f"{length}('email')") == len(SECRET.username)
        assert await page_js(chrome, url, f"{length}('password')") == len(SECRET.password)
        assert (await f(selector="input[name=nope]", secret="password"))["message"] == "no element matches that selector"
    asyncio.run(go())
