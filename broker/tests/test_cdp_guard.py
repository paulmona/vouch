"""browser/cdp-guard: what it would load, without loading it."""
import subprocess
from pathlib import Path

GUARD = Path(__file__).parents[2] / "browser" / "cdp-guard"


def rules(tmp_path, ports: str):
    f = tmp_path / "ports"
    f.write_text(ports)
    return subprocess.run([GUARD, "print"], env={"PATH": "/usr/sbin:/usr/bin:/sbin:/bin", "VOUCH_BROWSER_PORTS": str(f),
                                                 "VOUCH_BROKER_USER": "daemon"}, capture_output=True, text=True)



def test_one_bad_line_does_not_leave_the_other_ports_open(tmp_path):
    r = rules(tmp_path, "root 9222\nno-such-user 9223\ndaemon not-a-port\nroot 9224\n")
    assert 'tcp dport 9222 meta skuid { 0, 1 } accept' in r.stdout
    assert 'tcp dport 9224 meta skuid { 0, 1 } accept' in r.stdout
    assert r.stdout.count("reject with tcp reset") == 3
    # The port of a user that does not exist is closed to everyone, not left open.
    assert "tcp dport 9223 counter reject" in r.stdout and "dport 9223 meta skuid" not in r.stdout
    assert r.returncode != 0 and "no such user: no-such-user" in r.stderr and "bad port for daemon" in r.stderr


def test_a_clean_file_exits_zero(tmp_path):
    r = rules(tmp_path, "# agents\nroot 9222\n")
    assert r.returncode == 0 and r.stdout.count(" accept\n") == 1


def test_the_failure_message_names_the_command_that_clears_the_failed_unit():
    # `load` itself needs root and nftables, so this reads the message from the script.
    # A plain `vouch-cdp-guard load` after the fix leaves the unit showing failed until the next boot.
    (line,) = [l for l in GUARD.read_text().splitlines() if "were not usable" in l]
    assert "systemctl restart vouch-cdp-guard" in line and "run 'vouch-cdp-guard load'" not in line
