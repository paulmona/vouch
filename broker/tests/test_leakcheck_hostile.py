"""The leak check runs as root over files the agents own: it must not be stalled or misdirected
by them, and a check that did not run must not look like a clean one.

Nothing here can hang: the blocking cases run in a subprocess with a timeout, and /proc/kmsg
is never actually opened.
"""
import asyncio
import os
import re
import subprocess
import sys
from pathlib import Path

from test_leakcheck import ALERTS, setup

from credbroker import leakcheck
from credbroker.config import Leakcheck
from credbroker.leakcheck import Secret, scan

PW = Secret("research", "Example", "password", "long-enough-pw")
UNIT = Path(__file__).parents[1] / "deploy" / "credbroker-leakcheck.service"


def test_scan_does_not_open_a_symlink_to_proc_kmsg(tmp_path, monkeypatch):
    """/proc/kmsg is a regular file by type, size 0, and a root read of it never ends.

    The read is intercepted, so this is safe to run as root too.
    """
    (tmp_path / "notes.jsonl").symlink_to("/proc/kmsg")
    opened = []
    real = Path.read_bytes

    def read_bytes(self):
        if os.path.realpath(self) == "/proc/kmsg":
            opened.append(str(self))
            raise PermissionError  # what an unprivileged read gets; root would block here for good
        return real(self)
    monkeypatch.setattr(Path, "read_bytes", read_bytes)
    scan([tmp_path], [PW])
    assert opened == [], "scan() went on to read a symlink that points at /proc/kmsg"


def test_scan_does_not_walk_out_through_a_symlinked_root(tmp_path):
    """~/.claude replaced by a symlink (it could point at /; to an outside directory here)."""
    outside = tmp_path / "outside"
    (outside / "etc").mkdir(parents=True)
    (outside / "etc" / "shadow").write_text("not the agent's file")
    home = tmp_path / "home" / "research"
    home.mkdir(parents=True)
    if os.geteuid() == 0:
        os.chown(home, 65534, 65534)   # an agent's home; in one root owns, a link is root's own choice
    (home / ".claude").symlink_to(outside)
    hits, files = scan([home / ".claude"], [PW])
    assert files == 0, f"scan() followed the symlinked root and read {files} file(s) outside the agent's home"


def test_scan_does_not_read_a_file_symlink_that_leaves_the_root(tmp_path):
    outside = tmp_path / "outside.txt"
    outside.write_text(PW.value)
    root = tmp_path / "root"
    root.mkdir()
    (root / "link.txt").symlink_to(outside)
    hits, files = scan([root], [PW])
    assert files == 0 and hits == []


def test_scan_returns_when_a_fifo_or_a_symlink_to_one_is_in_the_way(tmp_path):
    """The stand-in the task suggested. Run in a subprocess so a hang cannot outlive the test."""
    os.mkfifo(tmp_path / "pipe")
    (tmp_path / "link").symlink_to(tmp_path / "pipe")
    code = ("import sys; from pathlib import Path; from credbroker.leakcheck import scan;"
            "print(scan([Path(sys.argv[1])], [])[1])")
    r = subprocess.run([sys.executable, "-c", code, str(tmp_path)], capture_output=True, text=True, timeout=10)
    assert r.returncode == 0 and r.stdout.strip() == "0"


def test_canary_is_not_written_through_a_symlink(monkeypatch, tmp_path):
    """--canary writes as root; whoever owns the directory can point the path elsewhere first."""
    victim = tmp_path / "victim.conf"
    victim.write_text("important\n")
    scanned = tmp_path / "scanned"
    scanned.mkdir()
    (scanned / "canary.jsonl").symlink_to(victim)
    setup(monkeypatch, Leakcheck(roots=(str(scanned),), canary_file=str(scanned / "canary.jsonl")))
    try:
        asyncio.run(leakcheck.run(canary=True))
    except OSError:
        pass  # refusing to write is the secure outcome
    assert victim.read_text() == "important\n", "the canary was written through the symlink, over another file"


def test_a_crashed_check_is_not_a_success_for_systemd(tmp_path):
    """An uncaught exception exits 1, and the unit lists 1 as success (it is also "a leak was found")."""
    ok = {int(n) for n in re.search(r"^SuccessExitStatus=(.*)$", UNIT.read_text(), re.M).group(1).split()} | {0}
    bad = tmp_path / "config.toml"
    bad.write_text("[nonsense]\n")  # config.load raises ValueError: any uncaught exception will do
    r = subprocess.run([sys.executable, "-c", "from credbroker.leakcheck import main; main()"],
                       env={**os.environ, "CREDBROKER_CONFIG": str(bad), "CREDBROKER_VOUCH_SOCKET": str(tmp_path / "none")},
                       capture_output=True, text=True, timeout=30)
    assert "Traceback" in r.stderr
    assert r.returncode not in ok, f"a crash exits {r.returncode}, which the unit accepts as success ({sorted(ok)})"


def test_unit_has_a_start_timeout():
    """Type=oneshot has no start timeout unless one is set, so one blocking read stops the daily check for good."""
    assert re.search(r"^(TimeoutStartSec|RuntimeMaxSec)=", UNIT.read_text(), re.M)


def test_a_check_that_crashed_alerts_the_owner(monkeypatch, tmp_path):
    setup(monkeypatch, Leakcheck(roots=(str(tmp_path),)))
    code, alerts = None, None

    async def boom(agents, env, unread):
        raise RuntimeError("1Password is down")
    monkeypatch.setattr(leakcheck, "load", boom)
    monkeypatch.setattr(sys, "argv", ["credbroker-leakcheck"])
    monkeypatch.setattr(leakcheck.os, "_exit", lambda c: (_ for _ in ()).throw(SystemExit(c)))
    try:
        leakcheck.main()
    except SystemExit as e:
        code, alerts = e.code, list(ALERTS)
    assert code == leakcheck.EXIT_FAILED
    assert len(alerts) == 1 and "did not finish" in alerts[0][2] and "RuntimeError" in alerts[0][3]
    assert "1Password is down" not in alerts[0][3]   # the alert names the kind of error, not its text


def test_a_read_that_never_returns_ends_the_check_with_an_alert(tmp_path):
    """A file on a filesystem the agent controls can block a read for ever. The check stops, says so, and exits."""
    code = (
        "import sys, time\n"
        "from credbroker import leakcheck\n"
        "from credbroker.config import Config, Leakcheck, Mqtt\n"
        "leakcheck.SCAN_TIMEOUT = leakcheck.GRACE = 1\n"
        "leakcheck.scan = lambda *a: time.sleep(600)\n"
        "leakcheck.journal = lambda: [b'']\n"
        "leakcheck.config.load = lambda: Config({}, Leakcheck(roots=('/',)), Mqtt())\n"
        "import credbroker.secretstore as ss; ss.load_secrets = lambda: {}\n"
        "class V:\n"
        "    def __init__(self, path): pass\n"
        "    def alert(self, *a): print('ALERT', a[2], flush=True)\n"
        "leakcheck.VouchApprovals = V\n"
        "sys.argv = ['credbroker-leakcheck']\n"
        "leakcheck.main()\n")
    r = subprocess.run([sys.executable, "-c", code], capture_output=True, text=True, timeout=30)
    assert r.returncode == leakcheck.EXIT_FAILED
    assert "ALERT The daily leak check did not finish" in r.stdout


def test_a_leak_and_a_failure_exit_differently():
    ok = {int(n) for n in re.search(r"^SuccessExitStatus=(.*)$", UNIT.read_text(), re.M).group(1).split()}
    assert leakcheck.EXIT_LEAK in ok and leakcheck.EXIT_FAILED not in ok and leakcheck.EXIT_LEAK != leakcheck.EXIT_FAILED
