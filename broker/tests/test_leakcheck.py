import asyncio
import json
import logging

import pytest

from credbroker import leakcheck
from credbroker.config import Agent, Config, Leakcheck, Mqtt
from credbroker.leakcheck import Secret, scan
from credbroker.onepw import Credentials, Login, Website

PW = Secret("research", "Example", "password", 'hunter2"\\x')


def test_finds_raw_and_json_escaped(tmp_path):
    (tmp_path / "plain.txt").write_text(f"oops {PW.value} oops")
    (tmp_path / "t.jsonl").write_text(json.dumps({"content": f"pasted {PW.value}"}) + "\n")
    (tmp_path / "clean.md").write_text("nothing to see")
    hits, files = scan([tmp_path], [PW])
    assert sorted(h.where.rsplit("/", 1)[1] for h in hits) == ["plain.txt", "t.jsonl"] and files == 3


def test_skips_browser_profile_and_caches(tmp_path):
    for d in ("chrome-profile", "node_modules", "cache"):
        (tmp_path / d).mkdir()
        (tmp_path / d / "f").write_text(PW.value)
    assert scan([tmp_path], [PW])[0] == []


def test_secret_value_never_in_repr():
    assert PW.value not in repr(PW) and PW.value not in repr(leakcheck.Hit(PW, "/x"))


class Vault:
    def __init__(self, agent, token):
        pass

    async def logins(self, fresh=False):
        return [Login("a", "Example", (Website("https://x", "AnywhereOnWebsite"),))]

    async def credentials(self, login_id):
        return Credentials("alex", "long-enough-pw", {"Your first car": "Corolla", "Mother's middle name": "Ann"})


def test_load_skips_short_values_and_agents_without_tokens(monkeypatch):
    monkeypatch.setattr(leakcheck, "AgentVault", Vault)
    agents = {1: Agent("research", 1, op_token_key="OP_RESEARCH"), 2: Agent("assistant", 2)}
    secrets, short = asyncio.run(leakcheck.load(agents, {"OP_RESEARCH": "t"}))
    assert sorted((s.kind, s.value) for s in secrets) == [("answer", "Corolla"), ("password", "long-enough-pw")]
    assert short == 1


def setup(monkeypatch, lc, mqtt=None):
    """Returns the list that collects what the leak check publishes to MQTT."""
    published = []
    monkeypatch.setattr(leakcheck, "journal", lambda: [b""])
    monkeypatch.setattr(leakcheck, "AgentVault", Vault)
    monkeypatch.setattr(leakcheck.config, "load",
                        lambda: Config({1: Agent("research", 1, op_token_key="OP_RESEARCH")}, lc, mqtt or Mqtt()))
    monkeypatch.setattr("credbroker.secretstore.load_secrets", lambda: {"OP_RESEARCH": "t"})
    monkeypatch.setattr(leakcheck.events, "publish_once", lambda cfg, secrets, payload: published.append((cfg, payload)))
    ALERTS.clear()
    monkeypatch.setattr(leakcheck, "VouchApprovals", FakeVouch)
    return published


ALERTS: list[tuple] = []


class FakeVouch:
    down = False

    def __init__(self, path):
        pass

    def alert(self, alert_id, severity, title, body):
        if self.down:
            raise leakcheck.ApprovalError("Vouch is down")
        ALERTS.append((alert_id, severity, title, body))


def test_a_hit_alerts_the_owners_phone_without_the_value(monkeypatch, tmp_path):
    (tmp_path / "leak.jsonl").write_text("the password is long-enough-pw")
    setup(monkeypatch, Leakcheck(roots=(str(tmp_path),)))
    assert asyncio.run(leakcheck.run()) == leakcheck.EXIT_LEAK
    ((alert_id, severity, title, body),) = ALERTS
    assert alert_id.startswith("leak_") and severity == "critical"
    assert "research/Example (password)" in body and "leak.jsonl" in body
    assert "long-enough-pw" not in title + body


def test_vouch_being_down_does_not_hide_the_hit(monkeypatch, tmp_path, caplog):
    (tmp_path / "leak.jsonl").write_text("the password is long-enough-pw")
    setup(monkeypatch, Leakcheck(roots=(str(tmp_path),)))
    monkeypatch.setattr(FakeVouch, "down", True)
    assert asyncio.run(leakcheck.run()) == leakcheck.EXIT_LEAK
    assert "could not alert the owner's phone" in caplog.text and "possible leak" in caplog.text


def test_a_clean_run_sends_no_alert(monkeypatch, tmp_path):
    (tmp_path / "ok.jsonl").write_text("nothing here")
    setup(monkeypatch, Leakcheck(roots=(str(tmp_path),)))
    assert asyncio.run(leakcheck.run()) == 0
    assert ALERTS == []


def test_a_hit_is_logged_and_exits_1_without_mqtt(monkeypatch, tmp_path, caplog):
    (tmp_path / "leak.jsonl").write_text("the password is long-enough-pw")
    published = setup(monkeypatch, Leakcheck(roots=(str(tmp_path),)))
    caplog.set_level(logging.ERROR)
    assert asyncio.run(leakcheck.run()) == leakcheck.EXIT_LEAK
    (r,) = caplog.records
    assert r.levelno == logging.ERROR
    assert "leak.jsonl" in r.getMessage() and "research/Example (password)" in r.getMessage()
    assert "long-enough-pw" not in caplog.text
    assert published == []


def test_a_hit_publishes_one_event_without_the_value_when_mqtt_is_on(monkeypatch, tmp_path):
    (tmp_path / "leak.jsonl").write_text("the password is long-enough-pw")
    mqtt = Mqtt(url="mqtt://broker.example")
    published = setup(monkeypatch, Leakcheck(roots=(str(tmp_path),)), mqtt)
    assert asyncio.run(leakcheck.run()) == leakcheck.EXIT_LEAK
    ((cfg, e),) = published
    assert cfg is mqtt and set(e) == {"ts", "kind", "count", "places"}
    assert (e["kind"], e["count"]) == ("leak", 1)
    assert e["places"] == [f"research/Example (password) in {tmp_path / 'leak.jsonl'}"]
    assert "long-enough-pw" not in json.dumps(e)


def test_mqtt_being_down_does_not_hide_the_hit(monkeypatch, tmp_path, caplog):
    (tmp_path / "leak.jsonl").write_text("the password is long-enough-pw")
    setup(monkeypatch, Leakcheck(roots=(str(tmp_path),)), Mqtt(url="mqtt://broker.example"))

    def down(cfg, secrets, payload):
        raise ConnectionRefusedError
    monkeypatch.setattr(leakcheck.events, "publish_once", down)
    assert asyncio.run(leakcheck.run()) == leakcheck.EXIT_LEAK
    assert "possible leak" in caplog.text and "could not publish" in caplog.text


def test_clean_run_is_silent(monkeypatch, tmp_path, caplog):
    (tmp_path / "ok.md").write_text("fine")
    published = setup(monkeypatch, Leakcheck(roots=(str(tmp_path),)), Mqtt(url="mqtt://broker.example"))
    caplog.set_level(logging.WARNING)
    assert asyncio.run(leakcheck.run()) == 0 and published == [] and caplog.records == []


def test_canary_is_found_reported_and_removed(monkeypatch, tmp_path, caplog):
    (tmp_path / "a").mkdir()
    canary = tmp_path / "a" / "canary.jsonl"
    published = setup(monkeypatch, Leakcheck(roots=(str(tmp_path / "*"),), canary_file=str(canary)),
                      Mqtt(url="mqtt://broker.example"))
    assert asyncio.run(leakcheck.run(canary=True)) == leakcheck.EXIT_LEAK
    assert "canary/TEST canary" in caplog.text and str(canary) in caplog.text and not canary.exists()
    assert "canary/TEST canary" in published[0][1]["places"][0]


def test_canary_needs_a_configured_file(monkeypatch, tmp_path):
    setup(monkeypatch, Leakcheck(roots=(str(tmp_path),)))
    with pytest.raises(SystemExit, match="canary_file"):
        asyncio.run(leakcheck.run(canary=True))


def test_the_phone_is_told_before_the_event_is_published(monkeypatch, tmp_path):
    (tmp_path / "leak.jsonl").write_text("the password is long-enough-pw")
    setup(monkeypatch, Leakcheck(roots=(str(tmp_path),)), Mqtt(url="mqtt://broker.example"))
    seen = []
    monkeypatch.setattr(leakcheck.events, "publish_once", lambda cfg, secrets, payload: seen.append(list(ALERTS)))
    assert asyncio.run(leakcheck.run()) == leakcheck.EXIT_LEAK
    ((alert,),) = seen
    assert alert[2] == "A password is where an agent can read it", "the event was published before the alert was sent"


def test_a_publish_error_nobody_expected_does_not_hide_the_hit(monkeypatch, tmp_path, caplog):
    """The MQTT client can fail in ways this code does not list. Whatever it raises, the leak
    alert has been sent and the run still ends as a leak, not as a check that did not run."""
    (tmp_path / "leak.jsonl").write_text("the password is long-enough-pw")
    setup(monkeypatch, Leakcheck(roots=(str(tmp_path),)), Mqtt(url="mqtt://broker.example"))

    class Odd(Exception):
        pass

    def broken(cfg, secrets, payload):
        raise Odd
    monkeypatch.setattr(leakcheck.events, "publish_once", broken)
    assert asyncio.run(leakcheck.run()) == leakcheck.EXIT_LEAK
    assert [a[2] for a in ALERTS] == ["A password is where an agent can read it"]
    assert "could not publish the leak event: Odd" in caplog.text
