"""The page address comes from the agent. One that is too long to be a real address is
refused before it is stored, logged or published: nothing downstream has to cope with it."""
import asyncio
import logging

import pytest
from test_events import FakeClient
from test_signin import RESEARCH, Approvals, Vault, env  # noqa: F401 - env is a fixture

from credbroker.config import Mqtt
from credbroker.events import Bus
from credbroker.server import Broker
from credbroker.store import Store

LONG = "https://portal.example.com/login?" + "a" * 60_000
OPS = ["sign_in", "begin_sign_in"]


def broker(tmp_path):
    bus = Bus(Mqtt(url="mqtt://broker.example:1883"), {})
    bus.client = FakeClient()
    store = Store(tmp_path / "b.db")
    return Broker({1003: RESEARCH}, {"research": Vault()}, store, Approvals(), bus), bus, store


def rows(store):
    return store._q("SELECT site FROM requests")


@pytest.mark.parametrize("op", OPS)
def test_a_page_address_that_is_too_long_is_refused_and_kept_nowhere(env, tmp_path, caplog, op):
    b, bus, store = broker(tmp_path)
    with caplog.at_level(logging.DEBUG, logger="credbroker"):
        r = asyncio.run(getattr(b, op)(RESEARCH, {"url": LONG, "reason": "check the balance"}))
    assert [len(s[0]) for s in rows(store)] == [], "the address was stored"
    assert [len(p[1]) for p in bus.client.published] == [], "the address was published"
    assert [len(m) for rec in caplog.records if len(m := rec.getMessage()) > 1000] == [], "the address reached the log"
    assert r.get("error") == "url_too_long" and "aaaa" not in str(r)


@pytest.mark.parametrize("op", OPS)
def test_an_address_at_the_limit_is_still_taken(env, tmp_path, op):
    b, bus, store = broker(tmp_path)
    url = "https://portal.example.com/login?" + "a" * (2048 - 33)
    assert len(url) == 2048
    r = asyncio.run(getattr(b, op)(RESEARCH, {"url": url, "reason": "check the balance"}))
    assert r.get("error") != "url_too_long"
    assert [len(s[0]) for s in rows(store)] == [2048]
