"""One agent's hits must not keep another agent's hit, or the journal's, off the owner's phone.

Vouch cuts an alert at 2,000 characters. The alert is built to fit: totals per agent first,
then places taken from each agent in turn, each shortened to its end, then how many were left
out. These tests send the alert through the real cut.
"""
import asyncio
import os
import subprocess

import pytest
from test_leakcheck import setup

from credbroker import leakcheck
from credbroker.approval import VouchApprovals
from credbroker.config import Agent, Config, Leakcheck, Mqtt
from credbroker.onepw import Credentials, Login, Website

PW = {"assistant": "assistant-own-pw", "research": "research-own-pw"}
LEAK = "A password is where an agent can read it"
DEPTH = 1100


class Vault:
    def __init__(self, agent, token):
        self.agent = agent

    async def logins(self, fresh=False):
        return [Login("a", "Example", (Website("https://x", "AnywhereOnWebsite"),))]

    async def credentials(self, login_id):
        return Credentials("alex", PW[self.agent], {})


@pytest.fixture
def sent(monkeypatch, tmp_path):
    """Two agents, each with a folder, and what reaches Vouch after the real cut. `assistant`
    sorts first and is the one that crowds; `research` has one leak, in a file and in the journal."""
    for name in PW:
        (tmp_path / name).mkdir()
    (tmp_path / "research" / "leak.jsonl").write_text(f"typed {PW['research']}")
    mqtt = Mqtt(url="mqtt://broker.example")
    published = setup(monkeypatch, Leakcheck(roots=(str(tmp_path / "*"),)), mqtt)
    monkeypatch.setattr(leakcheck, "journal", lambda: [f"fill: typed {PW['research']}".encode()])
    monkeypatch.setattr(leakcheck, "AgentVault", Vault)
    agents = {i: Agent(name, i, op_token_key="OP_" + name.upper()) for i, name in enumerate(PW, 1)}
    monkeypatch.setattr(leakcheck.config, "load", lambda: Config(agents, Leakcheck(roots=(str(tmp_path / "*"),)), mqtt))
    monkeypatch.setattr("credbroker.secretstore.load_secrets", lambda: {"OP_ASSISTANT": "t", "OP_RESEARCH": "t"})
    alerts = {}

    def call(self, method, target, body=None):
        alerts[body["title"]] = body["body"]
        return 202, {}
    monkeypatch.setattr(leakcheck, "VouchApprovals", VouchApprovals)
    monkeypatch.setattr(VouchApprovals, "_call", call)
    return alerts, published


def test_one_place_with_a_very_long_name_does_not_cut_the_other_agents_hit(sent, tmp_path, caplog):
    alerts, published = sent
    fd = os.open(tmp_path / "assistant", os.O_RDONLY | os.O_DIRECTORY)
    try:
        for _ in range(DEPTH):
            os.mkdir("d", dir_fd=fd)
            below = os.open("d", os.O_RDONLY | os.O_DIRECTORY, dir_fd=fd)
            os.close(fd)
            fd = below
        with open(os.open("bottom.txt", os.O_WRONLY | os.O_CREAT, 0o600, dir_fd=fd), "w") as f:
            f.write(f"my own: {PW['assistant']}")
    finally:
        os.close(fd)
    try:
        assert asyncio.run(leakcheck.run()) == leakcheck.EXIT_LEAK
    finally:
        subprocess.run(["rm", "-rf", str(tmp_path / "assistant")], check=True)   # pytest's own cleanup cannot go this deep
    body = alerts[LEAK]
    assert "research/Example (password)" in body, "the other agent's hit was cut from the alert"
    assert str(tmp_path / "research" / "leak.jsonl") in body
    assert "journal of credbroker.service" in body, "the journal hit was cut from the alert"
    assert "assistant: 1" in body and "research: 2" in body, "the alert does not open with totals per agent"
    assert "d/d/d/bottom.txt" in body, "the long place does not keep its end"
    assert max(len(line) for line in body.split("\n")[2:]) <= leakcheck.PLACE_LEN
    assert "more, see" not in body   # nothing was left out, only shortened
    ((_, event),) = published
    assert event["count"] == 3 and len(event["places"]) == 3
    assert any("research/Example" in p and "leak.jsonl" in p for p in event["places"])
    assert all(len(p) <= leakcheck.PLACE_LEN for p in event["places"])
    assert "d/" * DEPTH + "bottom.txt" in caplog.text   # the log has the whole place


def test_many_hits_from_one_agent_do_not_push_out_the_other_agents_hit(sent, tmp_path, caplog):
    alerts, published = sent
    for i in range(25):
        (tmp_path / "assistant" / f"n{i:02}").write_text(PW["assistant"])
    assert asyncio.run(leakcheck.run()) == leakcheck.EXIT_LEAK
    body = alerts[LEAK]
    assert str(tmp_path / "research" / "leak.jsonl") in body, "the other agent's hit was pushed out of the alert"
    assert "journal of credbroker.service" in body, "the journal hit was pushed out of the alert"
    assert "assistant: 25" in body and "research: 2" in body, "the alert does not open with totals per agent"
    left_out = 27 - (len(body.split("\n")) - 3)   # two opening lines, the places, the closing line
    assert 7 <= left_out < 27 - 4
    assert body.endswith(f"and {left_out} more, see the log: journalctl -u credbroker-leakcheck"), "the alert does not say it left places out"
    ((_, event),) = published
    assert event["count"] == 27 and len(event["places"]) == leakcheck.MAX_PLACES
    assert sum(p.startswith("research/") for p in event["places"]) == 2, "the event left out the other agent's hits"
    assert caplog.text.count("possible leak:") == 27


def test_the_alert_fits_whatever_the_names_are_and_always_ends_by_saying_what_was_left_out(sent, tmp_path):
    alerts, _ = sent
    for i in range(25):
        (tmp_path / "assistant" / f"{i:02}{'n' * 200}").write_text(PW["assistant"])
    assert asyncio.run(leakcheck.run()) == leakcheck.EXIT_LEAK
    body = alerts[LEAK]
    assert len(body) <= 2000 and "research/Example (password)" in body and "journal of credbroker.service" in body
    left_out = 27 - (len(body.split("\n")) - 3)
    assert left_out > 0 and body.endswith(f"and {left_out} more, see the log: journalctl -u credbroker-leakcheck")
