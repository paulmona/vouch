"""An agent chooses the names of its own files, and may own the folder the canary is planted in.
Neither may let it write a line of the report, or send a root write or delete somewhere else."""
import asyncio
import logging
import os

import pytest
from test_leakcheck import ALERTS, setup

from credbroker import leakcheck
from credbroker.config import Leakcheck, Mqtt

FORGED = "notes\nERROR possible leak: assistant-Bank (password) in x\r\x1b[2K .txt"


def test_a_file_name_cannot_add_a_line_to_the_alert_the_log_or_the_event(monkeypatch, tmp_path, caplog):
    (tmp_path / FORGED).write_text("the password is long-enough-pw")
    published = setup(monkeypatch, Leakcheck(roots=(str(tmp_path),)), Mqtt(url="mqtt://broker.example"))
    caplog.set_level(logging.ERROR)
    assert asyncio.run(leakcheck.run()) == leakcheck.EXIT_LEAK
    shown = f"research/Example (password) in {tmp_path}/notes?ERROR possible leak: assistant-Bank (password) in x??[2K?.txt"
    label = "research/Example (password) in "   # the alert and the event keep the end of a long place
    short = shown if len(shown) <= leakcheck.PLACE_LEN else label + "..." + shown[len(label) + 3 - leakcheck.PLACE_LEN:]
    ((_, _, _, body),) = ALERTS
    assert body.split("\n")[1:] == ["research: 1", short], "one found file is one line of the alert"
    (r,) = caplog.records
    assert r.getMessage() == "possible leak: " + shown
    assert published[0][1]["places"] == [short]


def test_a_folder_name_cannot_add_a_line_to_the_unfinished_report(monkeypatch, tmp_path, caplog):
    root = tmp_path / "home\nERROR leak check: not finished: somewhere else"
    root.mkdir()
    setup(monkeypatch, Leakcheck(roots=(str(tmp_path / "*"),)))

    def never(*a):
        raise TimeoutError
    monkeypatch.setattr(leakcheck, "scan", never)
    caplog.set_level(logging.ERROR)
    assert asyncio.run(leakcheck.run()) == leakcheck.EXIT_FAILED
    shown = f"{tmp_path}/home?ERROR leak check: not finished: somewhere else"
    assert [r.getMessage() for r in caplog.records] == ["leak check: not finished: " + shown]
    ((_, _, _, body),) = ALERTS
    assert body.split("\n")[1:-1] == [shown]


def test_the_canary_is_not_planted_through_a_linked_folder(monkeypatch, tmp_path):
    """The canary's folder may be an agent's. A link in its place must not send root's delete
    and write to a file of the same name somewhere else."""
    elsewhere = tmp_path / "elsewhere"
    elsewhere.mkdir()
    victim = elsewhere / "canary.jsonl"
    victim.write_text("important\n")
    home = tmp_path / "home"
    home.mkdir()
    if os.geteuid() == 0:
        os.chown(home, 65534, 65534)   # an agent's home; in one root owns, a link is root's own choice
    (home / "notes").symlink_to(elsewhere)
    setup(monkeypatch, Leakcheck(roots=(str(home),), canary_file=str(home / "notes" / "canary.jsonl")))
    with pytest.raises(SystemExit, match="canary_file"):
        asyncio.run(leakcheck.run(canary=True))
    assert victim.read_text() == "important\n"


def test_the_canary_cleanup_removes_only_the_file_it_planted(monkeypatch, tmp_path):
    """While the scan runs, the agent swaps the canary's folder for a link to another one."""
    elsewhere = tmp_path / "elsewhere"
    elsewhere.mkdir()
    victim = elsewhere / "canary.jsonl"
    victim.write_text("important\n")
    home = tmp_path / "home"
    (home / "notes").mkdir(parents=True)
    setup(monkeypatch, Leakcheck(roots=(str(home),), canary_file=str(home / "notes" / "canary.jsonl")))
    real = leakcheck.scan_each

    async def swap_then_scan(roots, secrets, *into):
        (home / "notes").rename(home / "moved")
        (home / "notes").symlink_to(elsewhere)
        return await real(roots, secrets, *into)
    monkeypatch.setattr(leakcheck, "scan_each", swap_then_scan)
    assert asyncio.run(leakcheck.run(canary=True)) == leakcheck.EXIT_LEAK
    assert victim.read_text() == "important\n", "the cleanup followed the link and removed another file"
    assert not (home / "moved" / "canary.jsonl").exists(), "the canary it planted is still there"


def test_the_canary_cleanup_leaves_a_file_put_in_its_place(monkeypatch, tmp_path):
    home = tmp_path / "home"
    home.mkdir()
    canary = home / "canary.jsonl"
    setup(monkeypatch, Leakcheck(roots=(str(home),), canary_file=str(canary)))
    real = leakcheck.scan_each

    async def replace_then_scan(roots, secrets, *into):
        canary.unlink()
        canary.write_text("not the canary\n")
        return await real(roots, secrets, *into)
    monkeypatch.setattr(leakcheck, "scan_each", replace_then_scan)
    asyncio.run(leakcheck.run(canary=True))
    assert canary.read_text() == "not the canary\n"
