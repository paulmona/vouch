import sqlite3

import pytest

from credbroker.store import MIGRATIONS, Store


@pytest.fixture
def store(tmp_path):
    return Store(tmp_path / "b.db")


def test_schema_created_and_versioned(tmp_path):
    Store(tmp_path / "b.db")
    db = sqlite3.connect(tmp_path / "b.db")
    assert db.execute("PRAGMA user_version").fetchone()[0] == len(MIGRATIONS)
    Store(tmp_path / "b.db")  # reopening does not re-run migrations


def test_request_lifecycle(store):
    rid = store.start_request("research", "https://portal.example.com", "check balance")
    store.update_request(rid, login_id="a", login_title="Example", decision="once",
                         notify_ms=800, decide_ms=4000, fill_ms=2100, result="signed_in")
    r = store.get_request(rid)
    assert (r["agent"], r["decision"], r["result"], r["fill_ms"]) == ("research", "once", "signed_in", 2100)


def test_request_rejects_unknown_fields_and_decisions(store):
    rid = store.start_request("research", "https://x", "r")
    with pytest.raises(ValueError):
        store.update_request(rid, agent="assistant")
    with pytest.raises(sqlite3.IntegrityError):
        store.update_request(rid, decision="maybe")


def test_grant_lookup_revoke(store):
    assert store.grant("research", "a", "Example")
    assert not store.grant("research", "a", "Example")
    assert store.is_standing("research", "a")
    assert not store.is_standing("assistant", "a")
    assert [x["login_title"] for x in store.approvals("research")] == ["Example"]
    assert store.approvals("assistant") == []
    assert store.revoke("research", "a", by="assistant")
    assert not store.is_standing("research", "a")
    assert not store.revoke("research", "a", by="assistant")
    assert store.approvals() == []
    assert store.grant("research", "a", "Example")  # can be granted again after revoke
