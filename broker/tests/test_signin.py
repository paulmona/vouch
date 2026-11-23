import asyncio
import json

import pytest

from credbroker import server
from credbroker.approval import Decision
from credbroker.cdp import BrowserError, Tab
from credbroker.config import Agent
from credbroker.events import EVENT_FIELDS
from credbroker.fill import FillResult
from credbroker.onepw import Credentials, Login, Website
from credbroker.server import Broker
from credbroker.store import Store

RESEARCH = Agent(name="research", uid=1003, cdp_port=9222)
PAGE = "https://portal.example.com/login"
EXAMPLE = Login("a", "Example", (Website("https://portal.example.com", "AnywhereOnWebsite"),))
SECRET = Credentials("alex@example.com", "correct horse")


class Vault:
    async def logins(self, fresh=False):
        return [EXAMPLE]

    async def credentials(self, login_id):
        return SECRET


class Approvals:
    def __init__(self, *answers):
        self.answers, self.prompts = list(answers), []

    async def ask(self, prompt):
        self.prompts.append(prompt)
        return Decision(self.answers.pop(0), 120, 3000)


class Bus:
    def __init__(self):
        self.events = []

    def emit(self, row):
        self.events.append({k: row.get(k) for k in EVENT_FIELDS})


class FakeSession:
    def __init__(self, tab):
        pass

    async def __aenter__(self):
        return self

    async def __aexit__(self, *a):
        pass


@pytest.fixture
def env(tmp_path, monkeypatch):
    tabs = {"url": PAGE, "fill": FillResult("signed_in", None, 2500), "filled": []}

    async def find_tab(port, url, owner):
        if url != PAGE:
            raise BrowserError("tab_not_found")
        return Tab("t1", tabs["url"], "ws://x")

    async def fake_fill(session, creds, check):
        tabs["filled"].append(check(tabs["url"]))
        return tabs["fill"]

    monkeypatch.setattr(server.cdp, "find_tab", find_tab)
    monkeypatch.setattr(server.cdp, "Session", FakeSession)
    monkeypatch.setattr(server, "fill", fake_fill)

    async def fillable(tab):
        return tabs.get("unfillable")
    monkeypatch.setattr(server, "fillable", fillable)

    def make(*answers):
        bus = Bus()
        b = Broker({1003: RESEARCH}, {"research": Vault()}, Store(tmp_path / "b.db"), Approvals(*answers), bus)
        return b, bus
    return make, tabs


def sign_in(b, url=PAGE, reason="check the balance"):
    return asyncio.run(b.sign_in(RESEARCH, {"url": url, "reason": reason}))


def no_secrets(*objs):
    text = json.dumps(objs)
    return SECRET.username not in text and SECRET.password not in text


def test_approved_sign_in(env):
    make, tabs = env
    b, bus = make("once")
    r = sign_in(b)
    assert r == {"ok": True, "result": "signed_in", "sign_out": server.SIGN_OUT % "portal.example.com"}
    assert tabs["filled"] == [True]
    (e,) = bus.events
    assert e["decision"] == "once" and e["result"] == "signed_in" and e["fill_ms"] == 2500
    assert e["login_title"] == "Example" and e["notify_ms"] == 120 and e["decide_ms"] == 3000
    assert b.approvals.prompts[0].site == "portal.example.com"
    assert b.approvals.prompts[0].username == SECRET.username  # stays in the broker
    assert no_secrets(r, bus.events)


@pytest.mark.parametrize("answer,result", [("deny", "denied"), ("timeout", "timeout")])
def test_refused(env, answer, result):
    make, tabs = env
    b, bus = make(answer)
    assert sign_in(b) == {"ok": False, "result": result}
    assert tabs["filled"] == [] and bus.events[0]["decision"] == answer


def test_lookalike_tab_never_prompts(env):
    make, tabs = env
    tabs["url"] = "https://portal.example.com.evil.com/login"
    b, bus = make()
    r = sign_in(b)
    assert r["result"] == "no_login" and "portal.example.com.evil.com" in r["reason"]
    assert b.approvals.prompts == [] and len(bus.events) == 1


def test_unfillable_page_never_prompts(env):
    make, tabs = env
    tabs["unfillable"] = "no password field on the page; for a multi-step login use begin_sign_in"
    b, bus = make()
    r = sign_in(b)
    assert r["result"] == "fill_failed" and "begin_sign_in" in r["reason"]
    assert b.approvals.prompts == [] and tabs["filled"] == []


def test_code_only_login_never_prompts(env):
    make, tabs = env
    b, bus = make()

    class CodeOnly(Vault):
        async def credentials(self, login_id):
            return Credentials("alex@example.com", "")
    b.vaults["research"] = CodeOnly()
    r = sign_in(b)
    assert r["result"] == "fill_failed" and "begin_sign_in" in r["reason"]
    assert b.approvals.prompts == [] and tabs["filled"] == []


def test_no_tab(env):
    make, _ = env
    b, _ = make()
    assert sign_in(b, url="https://elsewhere.example/") == {
        "ok": False, "result": "fill_failed", "reason": "no open tab shows that page"}


def test_standing_skips_prompt(env):
    make, _ = env
    b, bus = make("always")
    sign_in(b)
    assert sign_in(b) == {"ok": True, "result": "signed_in"}
    assert len(b.approvals.prompts) == 1 and bus.events[1]["decision"] == "standing"


def test_an_approval_for_once_tells_the_agent_to_sign_out(env):
    make, _ = env
    b, _ = make("once")
    r = sign_in(b)
    assert "once" in r["sign_out"] and "Sign out of portal.example.com" in r["sign_out"]


def test_always_allow_does_not_tell_the_agent_to_sign_out(env):
    make, _ = env
    b, _ = make("always")
    assert "sign_out" not in sign_in(b)
    assert "sign_out" not in sign_in(b)


def test_a_failed_sign_in_does_not_tell_the_agent_to_sign_out(env):
    make, tabs = env
    tabs["fill"] = FillResult("fill_failed", "no", 900)
    b, _ = make("once")
    assert "sign_out" not in sign_in(b)


def test_the_agent_is_told_up_front_to_sign_out_after_an_approval_for_once():
    from credbroker import mcp_server
    assert "sign_out" in mcp_server.INSTRUCTIONS
    assert "stay signed in between tasks" not in mcp_server.INSTRUCTIONS


def test_the_agent_is_told_up_front_not_to_sign_in_unasked_or_ask_again_after_a_no():
    from credbroker import mcp_server
    text = " ".join(mcp_server.INSTRUCTIONS.split())
    assert "Sign in only when the task in hand needs that site" in text
    assert "After `denied` or `timeout`, stop" in text
    assert "do not ask again unless they say so" in text


def test_the_repo_ships_instructions_an_owner_can_give_their_agent():
    from pathlib import Path
    root = Path(__file__).parents[2]
    example = root / "examples" / "agent-instructions.md"
    assert example.is_file()
    text = " ".join(example.read_text().split())
    for must in ("Never launch another browser", "The profile is your owner's", "Sign in only when the task needs it",
                 "`denied` or `timeout`: stop", "Never handle a password", "`sign_out` note",
                 "These are instructions, not controls"):
        assert must in text, must
    assert "examples/agent-instructions.md" in (root / "docs" / "broker.md").read_text()


def test_fill_failure_reason_passed_on(env):
    make, tabs = env
    tabs["fill"] = FillResult("fill_failed", "the site showed an error after submitting; the page says why", 900)
    b, _ = make("once")
    assert sign_in(b) == {"ok": False, "result": "fill_failed", "reason": "the site showed an error after submitting; the page says why"}


def test_agent_without_vault_or_browser(env, tmp_path):
    b = Broker({1: Agent("assistant", 1)}, {}, Store(tmp_path / "s.db"), Approvals(), Bus())
    r = asyncio.run(b.sign_in(Agent("assistant", 1), {"url": PAGE, "reason": "x"}))
    assert r["result"] == "no_login"


@pytest.mark.parametrize("req", [{}, {"url": PAGE}, {"url": PAGE, "reason": "  "}, {"url": 3, "reason": "x"}])
def test_bad_request(env, req):
    make, _ = env
    b, bus = make()
    assert asyncio.run(b.sign_in(RESEARCH, req))["error"] == "bad_request" and bus.events == []


def test_reason_is_trimmed_for_the_phone(env):
    make, _ = env
    b, _ = make("deny")
    sign_in(b, reason="line one\n\nline two " + "x" * 500)
    p = b.approvals.prompts[0].reason
    assert p.startswith("line one line two") and len(p) == server.MAX_REASON
