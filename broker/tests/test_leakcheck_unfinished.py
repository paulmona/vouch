"""The alert for a check that did not finish must not lose what an agent cannot add to.

An agent can add places that do not finish. The journal and the logins 1Password would not
hand over are named first, the text is built to fit what Vouch keeps, a cut list ends by
saying how many were left out, and only a full list says that everything else was checked.
These tests send the alert through the real cut.
"""
import asyncio
import subprocess

import pytest
from test_leakcheck import setup

from credbroker import leakcheck
from credbroker.approval import VouchApprovals
from credbroker.config import Leakcheck
from credbroker.onepw import Login, OnePasswordError, Website

UNFINISHED = "The daily leak check did not finish"


@pytest.fixture
def sent(monkeypatch, tmp_path):
    """What reaches Vouch, after the real cut, from a run whose journal cannot be read."""
    alerts = {}

    def run(pattern, vault=None):
        setup(monkeypatch, Leakcheck(roots=(str(tmp_path / pattern),)))
        if vault:
            monkeypatch.setattr(leakcheck, "AgentVault", vault)

        def stuck():
            raise subprocess.TimeoutExpired("journalctl", 120)
        monkeypatch.setattr(leakcheck, "journal", stuck)

        def call(self, method, target, body=None):
            alerts[body["title"]] = body["body"]
            return 202, {}
        monkeypatch.setattr(leakcheck, "VouchApprovals", VouchApprovals)
        monkeypatch.setattr(VouchApprovals, "_call", call)
        assert asyncio.run(leakcheck.run()) == leakcheck.EXIT_FAILED
        return alerts[UNFINISHED]
    return run


def test_25_unfinished_roots_do_not_push_the_journal_out_of_the_alert(sent, tmp_path, caplog):
    for i in range(25):
        (tmp_path / f"root{i:02}").write_text("a file where a folder should be")
    body = sent("root*")
    assert "the journal of credbroker.service" in body, "the journal is not named"
    assert body.index("the journal of credbroker.service") < body.index("root00"), "the journal is not named first"
    named = sum(f"root{i:02}" in body for i in range(25))
    assert 0 < named < 25
    assert body.endswith(f"and {25 - named} more, see the log: journalctl -u credbroker-leakcheck")
    assert "everything else was" not in body, "a cut list still says everything else was checked"
    assert len(body) <= leakcheck.ALERT_LEN
    assert all(f"root{i:02}" in caplog.text for i in range(25))   # the log has every one


def test_a_login_that_could_not_be_read_is_named_before_the_roots(sent, tmp_path):
    for i in range(25):
        (tmp_path / f"root{i:02}").write_text("a file where a folder should be")

    class Refuses:
        def __init__(self, agent, token):
            pass

        async def logins(self, fresh=False):
            return [Login("a", "Example", (Website("https://x", "AnywhereOnWebsite"),))]

        async def credentials(self, login_id):
            raise OnePasswordError("no")
    body = sent("root*", Refuses)
    line = "1 login(s) of research could not be read from 1Password"
    assert body.index("the journal of credbroker.service") < body.index(line) < body.index("root00")


def test_a_root_with_a_very_long_name_keeps_its_start_and_its_end(sent, tmp_path):
    long = tmp_path / ("x" * 200)
    long.mkdir()
    (long / ("y" * 200)).write_text("a file where a folder should be")
    (tmp_path / "plain").write_text("a file where a folder should be")
    body = sent("*/*")   # one root, 400 characters and more
    assert max(len(line) for line in body.split("\n")[1:]) <= leakcheck.PLACE_LEN
    line = next(ln for ln in body.split("\n") if "yyy" in ln)
    assert line.startswith(str(tmp_path)[:40]) and line.endswith("(not a folder, or reached through a symbolic link)")


def test_a_short_list_is_whole_and_says_everything_else_was_checked(sent, tmp_path):
    (tmp_path / "root0").write_text("a file where a folder should be")
    body = sent("root*")
    assert "everything else was" in body and "root0" in body and "the journal of credbroker.service" in body
    assert body.endswith("See: journalctl -u credbroker-leakcheck") and "more, see" not in body
