"""No shape of one agent's folders may stop the check for the others, or pass as a clean run.

A service gets 1,024 open files by default. A walk that keeps one open per level of nesting
runs out in a chain of folders deeper than that, and a walk that calls itself per level runs
out of stack. Whatever goes wrong in one place must cost that one place at most.
"""
import asyncio
import os
import resource
import subprocess
import time

import pytest
from test_leakcheck import ALERTS, setup

from credbroker import leakcheck
from credbroker.config import Leakcheck
from credbroker.leakcheck import Secret, scan

PW = "long-enough-pw"   # what test_leakcheck's fake vault hands out
SECRET = Secret("research", "Example", "password", PW)
DEPTH = 1100


@pytest.fixture
def few_open_files():
    soft, hard = resource.getrlimit(resource.RLIMIT_NOFILE)
    resource.setrlimit(resource.RLIMIT_NOFILE, (min(1024, hard), hard))
    yield
    resource.setrlimit(resource.RLIMIT_NOFILE, (soft, hard))


@pytest.fixture
def homes(tmp_path):
    """Two agents' folders: one a chain of DEPTH folders with a leak at the bottom, one with a leak."""
    deep, honest = tmp_path / "a-deep" / ".claude", tmp_path / "b-honest" / ".claude"
    deep.mkdir(parents=True)
    honest.mkdir(parents=True)
    (honest / "leak.jsonl").write_text(f"the password is {PW}")
    fd = os.open(deep, os.O_RDONLY | os.O_DIRECTORY)
    try:
        for _ in range(DEPTH):
            os.mkdir("d", dir_fd=fd)
            below = os.open("d", os.O_RDONLY | os.O_DIRECTORY, dir_fd=fd)
            os.close(fd)
            fd = below
        with open(os.open("bottom.txt", os.O_WRONLY | os.O_CREAT, 0o600, dir_fd=fd), "w") as f:
            f.write(f"at the bottom: {PW}")
    finally:
        os.close(fd)
    yield deep, honest
    subprocess.run(["rm", "-rf", str(deep)], check=True)   # pytest's own cleanup cannot go this deep


def alerts():
    return {title: body for _, _, title, body in ALERTS}


def an_agents(folder):
    """As root, make `folder` an agent's: in a folder root owns, a link is root's own choice."""
    if os.geteuid() == 0:
        os.chown(folder, 65534, 65534)


def test_a_deep_chain_of_folders_in_one_home_does_not_stop_the_check(monkeypatch, tmp_path, homes, few_open_files):
    deep, honest = homes
    setup(monkeypatch, Leakcheck(roots=(str(tmp_path / "*" / ".claude"),)))
    monkeypatch.setattr(leakcheck, "journal", lambda: [f"fill: typed {PW}".encode()])
    code = asyncio.run(leakcheck.run())
    got = alerts()
    leak = got["A password is where an agent can read it"]
    assert str(honest / "leak.jsonl") in leak, "the leak in the other agent's files was not reported"
    assert "journal of credbroker.service" in leak, "the journal was not searched"
    assert "nothing was checked" not in "".join(got.values())
    if "The daily leak check did not finish" in got:   # the deep home may be given up on, but then by name
        assert str(deep) in got["The daily leak check did not finish"] and code == leakcheck.EXIT_FAILED
    else:
        assert code == leakcheck.EXIT_LEAK


def test_a_leak_at_the_bottom_of_a_deep_chain_is_found(homes, few_open_files):
    deep, _ = homes
    before = len(os.listdir("/proc/self/fd"))
    hits, files = scan([deep], [SECRET])
    assert [h.where for h in hits] == [os.path.join(deep, *["d"] * DEPTH, "bottom.txt")] and files == 1
    assert len(os.listdir("/proc/self/fd")) == before, "the walk left folders open"


def test_the_walk_holds_a_few_folders_open_however_deep_it_goes(homes, monkeypatch):
    deep, _ = homes
    most, real = [0], leakcheck._read

    def read(*a, **kw):
        most[0] = max(most[0], len(os.listdir("/proc/self/fd")))
        return real(*a, **kw)
    before = len(os.listdir("/proc/self/fd"))
    monkeypatch.setattr(leakcheck, "_read", read)
    scan([deep], [SECRET])
    assert 0 < most[0] - before <= 4, f"{most[0] - before} more files open at the bottom of the chain"


def test_an_error_in_one_place_costs_only_that_place(monkeypatch, tmp_path):
    broken, honest = tmp_path / "a-broken" / ".claude", tmp_path / "b-honest" / ".claude"
    broken.mkdir(parents=True)
    honest.mkdir(parents=True)
    (broken / "seen.txt").write_text(f"read before the error: {PW}")
    (broken / "zz-trap").write_text("x")
    (honest / "leak.jsonl").write_text(f"the password is {PW}")
    setup(monkeypatch, Leakcheck(roots=(str(tmp_path / "*" / ".claude"),)))
    real = leakcheck._read

    def read(name, *a, **kw):
        if name == "zz-trap":
            raise OSError(24, "Too many open files")
        return real(name, *a, **kw)
    monkeypatch.setattr(leakcheck, "_read", read)
    monkeypatch.setattr(leakcheck, "journal", lambda: [f"fill: typed {PW}".encode()])
    code = asyncio.run(leakcheck.run())
    got = alerts()
    leak = got["A password is where an agent can read it"]
    assert str(honest / "leak.jsonl") in leak and "journal of credbroker.service" in leak
    unfinished = got["The daily leak check did not finish"]
    assert str(broken) in unfinished and "OSError" in unfinished and str(honest) not in unfinished
    assert "nothing was checked" not in unfinished
    assert code == leakcheck.EXIT_FAILED


def test_what_was_found_before_the_error_is_still_reported(monkeypatch, tmp_path):
    root = tmp_path / "home" / ".claude"
    root.mkdir(parents=True)
    (root / "seen.txt").write_text(f"read before the error: {PW}")
    setup(monkeypatch, Leakcheck(roots=(str(root),)))

    def scan_then_fail(roots, secrets, hits, *a):
        hits.append(leakcheck.Hit(secrets[0], str(root / "seen.txt")))
        raise RecursionError
    monkeypatch.setattr(leakcheck, "scan", scan_then_fail)
    code = asyncio.run(leakcheck.run())
    got = alerts()
    assert str(root / "seen.txt") in got["A password is where an agent can read it"]
    assert "RecursionError" in got["The daily leak check did not finish"]
    assert code == leakcheck.EXIT_FAILED


def test_a_tree_of_empty_folders_stops_when_its_time_is_up(tmp_path):
    for i in range(50):
        (tmp_path / f"empty{i}" / "inner").mkdir(parents=True)
    with pytest.raises(TimeoutError):
        scan([tmp_path], [SECRET], deadline=time.monotonic() - 1)


def test_a_place_replaced_by_a_link_is_named_not_passed_over(monkeypatch, tmp_path):
    elsewhere = tmp_path / "elsewhere"
    elsewhere.mkdir()
    home, honest = tmp_path / "a-home", tmp_path / "b-honest" / ".claude"
    home.mkdir()
    an_agents(home)
    (home / ".claude").symlink_to(elsewhere)
    honest.mkdir(parents=True)
    setup(monkeypatch, Leakcheck(roots=(str(tmp_path / "*" / ".claude"),)))
    code = asyncio.run(leakcheck.run())
    got = alerts()
    assert str(home / ".claude") in got["The daily leak check did not finish"]
    assert str(honest) not in got["The daily leak check did not finish"]
    assert code == leakcheck.EXIT_FAILED


def test_every_place_replaced_by_a_link_is_not_a_clean_run(monkeypatch, tmp_path):
    elsewhere = tmp_path / "elsewhere"
    elsewhere.mkdir()
    home = tmp_path / "home"
    home.mkdir()
    an_agents(home)
    (home / ".claude").symlink_to(elsewhere)
    setup(monkeypatch, Leakcheck(roots=(str(home / ".claude"),)))
    assert asyncio.run(leakcheck.run()) == leakcheck.EXIT_FAILED
    assert str(home / ".claude") in alerts()["The daily leak check did not finish"]


def test_nowhere_to_look_is_not_a_clean_run(monkeypatch, tmp_path):
    setup(monkeypatch, Leakcheck(roots=(str(tmp_path / "*" / ".claude"), str(tmp_path / "missing"))))
    monkeypatch.setattr(leakcheck, "journal", lambda: [f"fill: typed {PW}".encode()])
    code = asyncio.run(leakcheck.run())
    got = alerts()
    assert "leakcheck.roots" in got["The daily leak check did not finish"]
    assert "journal of credbroker.service" in got["A password is where an agent can read it"], "the journal is still searched"
    assert code == leakcheck.EXIT_FAILED


def test_a_pattern_that_matches_nothing_is_fine_beside_one_that_does(monkeypatch, tmp_path):
    """A fresh install: no agent has a ~/.claude yet, and the broker's own data is there."""
    (tmp_path / "data").mkdir()
    setup(monkeypatch, Leakcheck(roots=(str(tmp_path / "*" / ".claude"), str(tmp_path / "data"))))
    assert asyncio.run(leakcheck.run()) == 0 and ALERTS == []
