"""One agent's files must not cost the others their check.

Each root (by default one per agent) gets its own share of the time. A root that runs out is
named; what was found elsewhere, and in the journal, is still reported.
"""
import asyncio
import subprocess
import time

from test_leakcheck import ALERTS, setup

from credbroker import leakcheck
from credbroker.config import Leakcheck

PW = "long-enough-pw"   # what test_leakcheck's fake vault hands out


def two_homes(tmp_path):
    hostile, honest = tmp_path / "a-hostile" / ".claude", tmp_path / "b-honest" / ".claude"
    hostile.mkdir(parents=True)
    honest.mkdir(parents=True)
    (honest / "leak.jsonl").write_text(f"the password is {PW}")
    return hostile, honest


def alerts():
    return {title: body for _, _, title, body in ALERTS}


def test_sparse_files_in_one_home_do_not_hide_a_leak_in_another(monkeypatch, tmp_path):
    hostile, honest = two_homes(tmp_path)
    for i in range(100):   # 6.4 GB to read, a few KB on disk
        with open(hostile / f"big{i}", "wb") as f:
            f.truncate(leakcheck.MAX_FILE)
    setup(monkeypatch, Leakcheck(roots=(str(tmp_path / "*" / ".claude"),)))
    monkeypatch.setattr(leakcheck, "journal", lambda: [f"fill: typed {PW}".encode()])
    monkeypatch.setattr(leakcheck, "SCAN_TIMEOUT", 2)
    started = time.monotonic()
    code = asyncio.run(leakcheck.run())
    assert time.monotonic() - started < 10
    got = alerts()
    leak = got["A password is where an agent can read it"]
    assert str(honest / "leak.jsonl") in leak, "the leak in the other agent's files was not reported"
    assert "journal of credbroker.service" in leak, "the journal was not searched"
    unfinished = got["The daily leak check did not finish"]
    assert str(hostile) in unfinished and str(honest) not in unfinished
    assert "nothing was checked" not in unfinished
    assert code == leakcheck.EXIT_FAILED   # the unit must show as failed: one home was not checked


def test_a_read_that_never_returns_costs_only_its_own_root(monkeypatch, tmp_path):
    hostile, honest = two_homes(tmp_path)
    (hostile / "stuck").write_text("x")
    setup(monkeypatch, Leakcheck(roots=(str(tmp_path / "*" / ".claude"),)))
    real = leakcheck._read

    def read(name, *a, **kw):
        if str(name).endswith("stuck"):
            time.sleep(30)
        return real(name, *a, **kw)
    monkeypatch.setattr(leakcheck, "_read", read)
    monkeypatch.setattr(leakcheck, "SCAN_TIMEOUT", 2)
    monkeypatch.setattr(leakcheck, "GRACE", 0.2, raising=False)
    code = asyncio.run(leakcheck.run())
    got = alerts()
    assert str(honest / "leak.jsonl") in got["A password is where an agent can read it"]
    assert str(hostile) in got["The daily leak check did not finish"]
    assert code == leakcheck.EXIT_FAILED


def test_a_journal_that_cannot_be_read_does_not_hide_a_leak_in_the_files(monkeypatch, tmp_path):
    _, honest = two_homes(tmp_path)
    setup(monkeypatch, Leakcheck(roots=(str(honest),)))

    def stuck():
        raise subprocess.TimeoutExpired("journalctl", 120)
    monkeypatch.setattr(leakcheck, "journal", stuck)
    code = asyncio.run(leakcheck.run())
    got = alerts()
    assert str(honest / "leak.jsonl") in got["A password is where an agent can read it"]
    assert "journal" in got["The daily leak check did not finish"]
    assert code == leakcheck.EXIT_FAILED


def test_a_run_that_checked_everything_still_exits_3_on_a_leak(monkeypatch, tmp_path):
    _, honest = two_homes(tmp_path)
    setup(monkeypatch, Leakcheck(roots=(str(honest),)))
    assert asyncio.run(leakcheck.run()) == leakcheck.EXIT_LEAK
    assert list(alerts()) == ["A password is where an agent can read it"]
