import asyncio

import pytest

from credbroker.approval import Decision
from credbroker.config import Agent
from credbroker.match import NoMatch
from credbroker.onepw import Login, Website
from credbroker.server import Broker
from credbroker.store import Store

RESEARCH = Agent(name="research", uid=1003)
ASSISTANT = Agent(name="assistant", uid=1002, admin=True)
EXAMPLE = Login("a", "Example", (Website("https://portal.example.com", "AnywhereOnWebsite"),))


class FakeVault:
    def __init__(self, logins):
        self.items, self.fresh_calls = list(logins), 0

    async def logins(self, fresh=False):
        self.fresh_calls += fresh
        return self.items


class FakeApprovals:
    def __init__(self, *answers):
        self.answers, self.prompts = list(answers), []

    async def ask(self, prompt):
        self.prompts.append(prompt)
        return Decision(self.answers.pop(0), 100, 2000)


def broker(tmp_path, *answers):
    vault = FakeVault([EXAMPLE])
    b = Broker({1003: RESEARCH, 1002: ASSISTANT}, {"research": vault}, Store(tmp_path / "b.db"), FakeApprovals(*answers))
    return b, vault


def authorize(b, n=1):
    return asyncio.run(b.authorize(RESEARCH, EXAMPLE, "https://portal.example.com/login",
                                   "alex", "check balance", f"r{n}"))


def test_approve_once_does_not_stick(tmp_path):
    b, _ = broker(tmp_path, "once", "deny")
    assert authorize(b).decision == "once"
    assert authorize(b, 2).decision == "deny"
    assert len(b.approvals.prompts) == 2 and b.store.approvals() == []


def test_always_then_standing_without_prompt(tmp_path):
    b, vault = broker(tmp_path, "always")
    assert authorize(b).decision == "always"
    d = authorize(b, 2)
    assert d == Decision("standing", 0, 0)
    assert len(b.approvals.prompts) == 1
    assert vault.fresh_calls == 1  # standing approvals check the vault, not the cache


def test_revoke_then_prompts_again(tmp_path):
    b, _ = broker(tmp_path, "always", "once")
    authorize(b)
    r = asyncio.run(b.revoke(ASSISTANT, {"agent": "research", "login": "example"}))
    assert r == {"ok": True, "revoked": 1}
    assert authorize(b, 2).decision == "once"
    assert len(b.approvals.prompts) == 2


def test_standing_stops_when_login_leaves_vault(tmp_path):
    b, vault = broker(tmp_path, "always")
    authorize(b)
    vault.items = []
    with pytest.raises(NoMatch) as e:
        authorize(b, 2)
    assert e.value.code == "no_login"
    assert b.store.approvals() == []
    row = b.store._q("SELECT revoked_by FROM standing_approvals")[0]
    assert row["revoked_by"] == "vault"


def test_an_agent_revokes_its_own_and_is_asked_again(tmp_path):
    b, _ = broker(tmp_path, "always", "once")
    authorize(b)
    assert asyncio.run(b.revoke(RESEARCH, {"login": "example"})) == {"ok": True, "revoked": 1}
    assert authorize(b, 2).decision == "once"
    assert b.store._q("SELECT revoked_by FROM standing_approvals")[0]["revoked_by"] == "research"


def test_only_admins_revoke_another_agents(tmp_path):
    b, _ = broker(tmp_path, "always")
    authorize(b)
    assert asyncio.run(b.revoke(RESEARCH, {"agent": "assistant", "login": "Example"})) == {"ok": False, "error": "not_admin"}
    assert asyncio.run(b.revoke(ASSISTANT, {"agent": "research", "login": "Nope"})) == {"ok": False, "error": "not_found"}
    assert asyncio.run(b.revoke(ASSISTANT, {"agent": 3})) == {"ok": False, "error": "bad_request"}


def test_approvals_listing_scope(tmp_path):
    b, _ = broker(tmp_path, "always")
    authorize(b)
    mine = asyncio.run(b.list_approvals(RESEARCH, {"all": True}))  # not admin: own only
    assert [a["agent"] for a in mine["approvals"]] == ["research"]
    assert asyncio.run(b.list_approvals(ASSISTANT, {}))["approvals"] == []
    assert len(asyncio.run(b.list_approvals(ASSISTANT, {"all": True}))["approvals"]) == 1


def test_approval_revoked_when_login_disappears_even_unused(tmp_path):
    b, vault = broker(tmp_path, "always")
    authorize(b)
    vault.items = []
    listing = asyncio.run(b.list_approvals(ASSISTANT, {"all": True}))
    assert listing["approvals"] == []
    assert b.store._q("SELECT revoked_by FROM standing_approvals")[0]["revoked_by"] == "vault"


def test_revoke_missing_keeps_present(tmp_path):
    s = Store(tmp_path / "s.db")
    s.grant("research", "a", "Example")
    s.grant("research", "t", "Test1")
    assert s.revoke_missing("research", {"a"}) == ["Test1"]
    assert [x["login_title"] for x in s.approvals("research")] == ["Example"]
