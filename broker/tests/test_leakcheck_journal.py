"""Whatever the journal step does, a leak already found in the files reaches the log and the
phone, and a journal that was not read to its end is named as not checked.

The broker logs a line for each request an agent makes, so an agent can make the journal large.
A stand-in `journalctl` on the PATH plays the real one.
"""
import asyncio
import os
import tracemalloc

import pytest
from test_leakcheck import ALERTS, setup

from credbroker import leakcheck
from credbroker.config import Leakcheck
from credbroker.leakcheck import Secret

PW = "long-enough-pw"   # what test_leakcheck's fake vault hands out
LEAK, UNFINISHED = "A password is where an agent can read it", "The daily leak check did not finish"
JOURNAL = leakcheck.journal   # the real one: setup() replaces it


def alerts():
    return {title: body for _, _, title, body in ALERTS}


@pytest.fixture
def leak(monkeypatch, tmp_path):
    """A leak in a file, and the real journal step. Returns the file."""
    home = tmp_path / "home"
    home.mkdir()
    (home / "leak.jsonl").write_text(f"the password is {PW}")
    setup(monkeypatch, Leakcheck(roots=(str(home),)))
    monkeypatch.setattr(leakcheck, "journal", JOURNAL)
    return home / "leak.jsonl"


def journalctl(monkeypatch, tmp_path, script):
    """Put a `journalctl` that runs `script` (sh) first on the PATH."""
    bin_ = tmp_path / "bin"
    bin_.mkdir()
    (bin_ / "journalctl").write_text("#!/bin/sh\n" + script + "\n")
    (bin_ / "journalctl").chmod(0o755)
    monkeypatch.setenv("PATH", f"{bin_}{os.pathsep}{os.environ['PATH']}")


@pytest.mark.parametrize("error", [MemoryError, RuntimeError, OSError])
def test_any_error_in_the_journal_step_leaves_the_file_hit_in_the_log_and_the_alert(monkeypatch, leak, caplog, error):
    def broken():
        raise error
    monkeypatch.setattr(leakcheck, "journal", broken)
    code = asyncio.run(leakcheck.run())
    assert f"possible leak: research/Example (password) in {leak}" in caplog.text
    got = alerts()
    assert str(leak) in got[LEAK]
    assert "the journal of credbroker.service" in got[UNFINISHED]
    assert code == leakcheck.EXIT_FAILED


def test_the_file_hit_is_logged_before_the_journal_is_read(monkeypatch, leak, caplog):
    seen = []

    def journal():
        seen.append("possible leak: research/Example (password)" in caplog.text)
        return [b""]
    monkeypatch.setattr(leakcheck, "journal", journal)
    assert asyncio.run(leakcheck.run()) == leakcheck.EXIT_LEAK
    assert seen == [True], "a run killed while it reads the journal would leave no line about the file"
    assert caplog.text.count("possible leak:") == 1


def test_a_journalctl_that_fails_is_not_a_journal_that_was_searched(monkeypatch, tmp_path, leak, caplog):
    leak.write_text("nothing here")
    journalctl(monkeypatch, tmp_path, "exit 1")
    code = asyncio.run(leakcheck.run())
    assert code == leakcheck.EXIT_FAILED, "a journalctl that exited 1 with no output passed as a clean run"
    assert "the journal of credbroker.service" in alerts()[UNFINISHED]
    assert "and the broker journal: 0 match(es)" not in caplog.text, "the log says the journal was searched"


def test_a_journalctl_that_fails_after_some_output_still_reports_what_it_showed(monkeypatch, tmp_path, leak):
    leak.write_text("nothing here")
    journalctl(monkeypatch, tmp_path, f"echo 'fill: typed {PW}'; exit 1")
    assert asyncio.run(leakcheck.run()) == leakcheck.EXIT_FAILED
    got = alerts()
    assert "journal of credbroker.service" in got[LEAK] and "the journal of credbroker.service" in got[UNFINISHED]


def test_a_large_journal_is_read_in_pieces_not_held_in_memory(monkeypatch, tmp_path, leak):
    """200 MB of journal, with the password at its very end."""
    journalctl(monkeypatch, tmp_path, f"head -c 200000000 /dev/zero; echo 'fill: typed {PW}'")
    tracemalloc.start()
    try:
        code = asyncio.run(leakcheck.run())
        peak = tracemalloc.get_traced_memory()[1]
    finally:
        tracemalloc.stop()
    assert peak < 32 * 2**20, f"reading the journal took {peak // 2**20} MiB of memory"
    assert code == leakcheck.EXIT_LEAK
    assert "journal of credbroker.service" in alerts()[LEAK] and str(leak) in alerts()[LEAK]


def test_a_journalctl_that_never_ends_is_stopped_and_named(monkeypatch, tmp_path, leak):
    journalctl(monkeypatch, tmp_path, "echo started; exec sleep 60")
    monkeypatch.setattr(leakcheck, "JOURNAL_TIMEOUT", 1, raising=False)
    code = asyncio.run(leakcheck.run())
    got = alerts()
    assert str(leak) in got[LEAK] and "the journal of credbroker.service" in got[UNFINISHED]
    assert code == leakcheck.EXIT_FAILED


def test_the_real_timeout_is_still_two_minutes():
    assert leakcheck.JOURNAL_TIMEOUT == 120


def test_a_secret_that_straddles_two_pieces_of_the_journal_is_found():
    short, long_ = Secret("research", "Short", "password", "sixsix"), Secret("research", "Long", "answer", "a" * 40 + "Z")
    absent = Secret("research", "Absent", "password", "not-in-there")
    data = b"x" * 100 + b"sixsix" + b"y" * 100 + b"a" * 40 + b"Z" + b"tail"
    for size in (1, 2, 5, 7, 41, 64, len(data)):
        pieces = [data[i:i + size] for i in range(0, len(data), size)]
        assert leakcheck.scan_chunks(pieces, [short, long_, absent]) == [short, long_], f"pieces of {size}"
    assert leakcheck.scan_chunks([b"six", b"-", b"six"], [short]) == []
    assert leakcheck.scan_chunks([], [short]) == [] and leakcheck.scan_chunks([b"sixsix"], []) == []


def test_a_login_that_could_not_be_read_from_1password_is_named_as_not_checked(monkeypatch, tmp_path, caplog):
    from test_leakcheck import Vault

    from credbroker.onepw import Login, OnePasswordError, Website

    class Flaky(Vault):
        async def logins(self, fresh=False):
            return [Login(i, f"Example {i}", (Website("https://x", "AnywhereOnWebsite"),)) for i in "abc"]

        async def credentials(self, login_id):
            if login_id != "a":
                raise OnePasswordError("rate limited")
            return await super().credentials(login_id)
    (tmp_path / "leak.jsonl").write_text(f"the password is {PW}")
    setup(monkeypatch, Leakcheck(roots=(str(tmp_path),)))
    monkeypatch.setattr(leakcheck, "AgentVault", Flaky)
    code = asyncio.run(leakcheck.run())
    assert code == leakcheck.EXIT_FAILED, "a login that was never checked passed as a full check"
    got = alerts()
    assert "2 login(s) of research could not be read from 1Password" in got[UNFINISHED]
    assert "research/Example b: could not be read from 1Password" in caplog.text
    assert str(tmp_path / "leak.jsonl") in got[LEAK]   # the login that was read is still checked
