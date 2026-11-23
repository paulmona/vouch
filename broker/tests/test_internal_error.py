"""A sign-in that goes wrong inside the broker still leaves a record, an event and a reply.

Without this only a dropped connection was caught, so anything else closed the
agent's connection with nothing said and nothing written down, after the owner had approved
and, in the worst case, after the password had been typed.
"""
import asyncio
import json
import logging
import socket

import pytest
from test_approval import FakeVouch, vouch  # noqa: F401 - vouch is a fixture
from test_cdp_trust import ME, Yes, attacker_port
from test_fill import chrome, open_tab, web  # noqa: F401 - chrome and web are fixtures
from test_signin import PAGE, RESEARCH, Bus, Vault, env, sign_in  # noqa: F401 - env is a fixture

from credbroker import cdp, server
from credbroker.approval import Prompt
from credbroker.config import Agent
from credbroker.onepw import Credentials, Login, Website
from credbroker.server import Broker
from credbroker.store import Store


def only_row(b):
    (row,) = b.store._q("SELECT * FROM requests")
    return dict(row)


def test_a_page_that_makes_the_click_throw_is_a_recorded_failed_fill(chrome, web, tmp_path):  # noqa: F811
    """The password is in the field by the time the submit button throws: the owner must
    be able to see afterwards that this sign-in was approved and what became of it."""
    url = f"{web}/throw.html"
    open_tab(chrome, url)

    class LocalVault:
        async def logins(self, fresh=False):
            return [Login("a", "Example", (Website(web, "AnywhereOnWebsite"),))]

        async def credentials(self, login_id):
            return Credentials("alex@example.com", "correct horse")

    agent = Agent("research", ME, cdp_port=chrome)
    bus = Bus()
    b = Broker({ME: agent}, {"research": LocalVault()}, Store(tmp_path / "b.db"), Yes(), bus)

    async def go():
        await asyncio.sleep(0.5)
        r = await b.sign_in(agent, {"url": url, "reason": "r"})
        async with cdp.Session(await cdp.find_tab(chrome, url, ME)) as s:
            typed = await s.send("Runtime.evaluate", {"expression": "document.getElementById('pw').value.length",
                                                      "returnByValue": True})
        return r, typed["result"]["value"]
    r, typed = asyncio.run(go())
    assert typed == len("correct horse"), "the password was not typed: the test is not exercising the failure"
    assert (r["ok"], r["result"]) == (False, "fill_failed")
    row = only_row(b)
    assert (row["decision"], row["result"]) == ("once", "fill_failed")
    assert [(e["decision"], e["result"]) for e in bus.events] == [("once", "fill_failed")]


def test_an_error_nobody_expected_still_records_the_approval_and_the_outcome(env, monkeypatch):  # noqa: F811
    make, tabs = env
    b, bus = make("once")

    async def broken_fill(session, creds, check):
        raise RuntimeError("correct horse")
    monkeypatch.setattr(server, "fill", broken_fill)
    with pytest.raises(RuntimeError):
        sign_in(b)
    row = only_row(b)
    assert (row["decision"], row["result"], row["login_title"]) == ("once", "error", "Example")
    assert [(e["decision"], e["result"]) for e in bus.events] == [("once", "error")]


def test_an_error_before_the_owner_answers_is_recorded_too(env, monkeypatch):  # noqa: F811
    make, tabs = env
    b, bus = make("once")

    async def find_tab(port, url, owner):
        raise RuntimeError("boom")
    monkeypatch.setattr(server.cdp, "find_tab", find_tab)
    with pytest.raises(RuntimeError):
        asyncio.run(b.begin_sign_in(RESEARCH, {"url": PAGE, "reason": "r"}))
    assert (only_row(b)["decision"], only_row(b)["result"]) == (None, "error")
    assert [e["result"] for e in bus.events] == ["error"]
    assert b.approvals.prompts == []


def test_the_agent_gets_a_reply_when_the_broker_fails_inside(tmp_path, caplog):
    """Not an empty line, which the client cannot parse. And the log names the kind of
    error only: an exception's message can repeat what a page said."""
    caplog.set_level(logging.INFO)
    path = str(tmp_path / "b.sock")
    agent = Agent("research", ME)
    b = Broker({ME: agent}, {}, Store(tmp_path / "b.db"))

    async def boom(agent, req):
        raise RuntimeError("correct horse")
    b.ops["whoami"] = boom

    async def go():
        srv = await b.serve(path, group=None)

        def ask():
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
                s.connect(path)
                s.sendall(b'{"op": "whoami"}\n')
                return s.makefile("rb").readline()
        try:
            return await asyncio.to_thread(ask)
        finally:
            srv.close()
    assert json.loads(asyncio.run(go())) == {"ok": False, "error": "internal"}
    assert "RuntimeError" in caplog.text and "correct horse" not in caplog.text


@pytest.mark.parametrize("refusal", ["down", 400])
def test_vouch_refusing_or_being_down_is_a_clear_failed_sign_in(env, vouch, tmp_path, refusal):  # noqa: F811
    make, tabs = env
    b, bus = make()
    if refusal == "down":
        from credbroker.approval import VouchApprovals
        b.approvals = VouchApprovals(str(tmp_path / "nobody-listens.sock"))
    else:
        _, b.approvals = vouch(create_status=refusal)
    r = sign_in(b)
    assert (r["ok"], r["result"]) == (False, "fill_failed")
    assert "phone" in r["reason"] and "nothing was typed" in r["reason"]
    assert tabs["filled"] == []
    assert (only_row(b)["decision"], only_row(b)["result"]) == (None, "fill_failed")
    assert [e["result"] for e in bus.events] == ["fill_failed"]


def test_a_long_login_title_is_cut_to_what_vouch_accepts(vouch):  # noqa: F811
    srv, approvals = vouch(polls=0)
    d = asyncio.run(approvals.ask(Prompt("ab12cd34ef56ab12", "research", "portal.example.com", "alex@example.com",
                                         "r", "T" * 300)))
    assert d.decision == "once"
    assert srv.created[0]["login_title"] == "T" * 200


def _tab_list(body: bytes):
    def get(self):
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    return get


@pytest.mark.parametrize("body", [
    b"[" * 100_000 + b"]" * 100_000,                                           # too deep to parse
    json.dumps([{"id": "p1", "type": "page", "url": 7}]).encode(),             # an address that is not text
    json.dumps([{"id": "p1", "type": "page", "url": ["https://portal.example.com/login"]}]).encode(),
    json.dumps([7, None, "x"]).encode(),
], ids=["nested", "url-number", "url-list", "not-objects"])
def test_a_tab_list_that_is_not_what_chrome_sends_is_a_failed_sign_in(tmp_path, body):
    srv = attacker_port(_tab_list(body))
    agent = Agent("research", ME, cdp_port=srv.server_address[1])
    b = Broker({ME: agent}, {"research": Vault()}, Store(tmp_path / "b.db"), Yes())
    try:
        r = asyncio.run(b.sign_in(agent, {"url": "https://portal.example.com/login", "reason": "r"}))
    finally:
        srv.shutdown()
    assert (r["ok"], r["result"]) == (False, "fill_failed")
    assert only_row(b)["result"] == "fill_failed"
