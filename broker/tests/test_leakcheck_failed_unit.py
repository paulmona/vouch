"""The backstop: whatever ends the leak check's unit as failed, the owner's phones are told.

systemd starts credbroker-leakcheck-failed.service when credbroker-leakcheck.service fails.
That unit runs one small script with the standard library only, so it does not depend on
anything the check itself needs. These tests run the real script against a stand-in for
Vouch's socket, and read the unit files. They do not run systemd.
"""
import re
import subprocess
import sys
import threading
from pathlib import Path

from test_approval import FakeVouch

DEPLOY = Path(__file__).parents[1] / "deploy"
SCRIPT = DEPLOY / "leakcheck-failed.py"
UNIT = (DEPLOY / "credbroker-leakcheck.service").read_text()
FAILED = (DEPLOY / "credbroker-leakcheck-failed.service").read_text()


def run(sock):
    """The script as the unit runs it: no site-packages, no user site, no environment of ours."""
    return subprocess.run([sys.executable, "-I", "-S", str(SCRIPT)], capture_output=True, text=True, timeout=60,
                          env={"CREDBROKER_VOUCH_SOCKET": str(sock)})


def test_the_script_sends_one_fixed_alert_through_vouch(tmp_path):
    with FakeVouch(tmp_path / "vouch.sock") as vouch:
        threading.Thread(target=vouch.serve_forever, daemon=True).start()
        r = run(tmp_path / "vouch.sock")
        vouch.shutdown()
    assert r.returncode == 0, r.stderr
    (alert,) = vouch.alerts
    assert alert["severity"] == "critical" and re.fullmatch(r"leakfail_[0-9a-f]{18}", alert["alert_id"])
    assert alert["title"] == "The daily leak check failed or was stopped"
    assert "is not complete" in alert["body"] and "journalctl -u credbroker-leakcheck" in alert["body"]
    assert len(alert["title"]) <= 120 and len(alert["body"]) <= 2000 and alert["body"].isascii()
    # a run that was killed after it logged a hit sent nothing: the owner is told where to look, and for what
    assert "Anything it had already found is in that log as 'possible leak' and was not sent to you." in alert["body"]
    assert all(line.isprintable() for line in alert["body"].split("\n"))


def test_the_script_uses_nothing_but_the_standard_library():
    """It must run when the broker's own packages are what stopped the check."""
    imports = set(re.findall(r"^(?:import|from) (\w+)", SCRIPT.read_text(), re.M))
    assert imports <= set(sys.stdlib_module_names), imports - set(sys.stdlib_module_names)
    assert "-I -S" in FAILED and "deploy/leakcheck-failed.py" in FAILED


def test_the_script_fails_loudly_when_vouch_is_not_there(tmp_path):
    r = run(tmp_path / "nothing.sock")
    assert r.returncode == 1 and "could not alert the owner's phone" in r.stderr


def test_the_script_fails_when_vouch_refuses(tmp_path):
    with FakeVouch(tmp_path / "vouch.sock") as vouch:
        vouch.alert_status = 503
        threading.Thread(target=vouch.serve_forever, daemon=True).start()
        r = run(tmp_path / "vouch.sock")
        vouch.shutdown()
    assert r.returncode == 1 and "HTTP 503" in r.stderr


def test_the_leak_check_unit_names_the_failure_unit_and_has_a_memory_limit():
    assert re.search(r"^OnFailure=credbroker-leakcheck-failed\.service$", UNIT, re.M)
    assert re.search(r"^MemoryMax=\d+[MG]$", UNIT, re.M)
    assert re.search(r"^Type=oneshot$", FAILED, re.M) and re.search(r"^TimeoutStartSec=", FAILED, re.M)


def test_the_installer_installs_the_failure_unit():
    assert '"$rel/deploy/$UNIT-leakcheck-failed.service"' in (DEPLOY / "install.sh").read_text()
