"""browser/chrome-start, where it can be run without a browser."""
import os
import pwd
import socket
import subprocess
import time
from pathlib import Path

import pytest

MARK = "vouch-chrome-start-test-listener"
CHROME_START = Path(__file__).parents[2] / "browser" / "chrome-start"
# A DevTools port that answers, as another user's Chrome would.
LISTENER = """
import http.server, sys, threading, os
threading.Timer(60, os._exit, [0]).start()   # never outlive the test by long
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.end_headers(); self.wfile.write(b'{"Browser":"Chrome"}')
    def log_message(self, *a): pass
http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
"""


def assigned(tmp_path, port: int, guarded: bool = True) -> dict[str, str]:
    """Environment in which chrome-start finds `port` assigned to this user, and (or not) guarded."""
    me = pwd.getpwuid(os.getuid()).pw_name
    ports, record = tmp_path / "ports", tmp_path / "guarded"
    ports.write_text(f"{me} {port}\n")
    record.write_text(f"{port} {os.getuid()}\n" if guarded else "")
    return {"VOUCH_BROWSER_PORTS": str(ports), "VOUCH_BROWSER_GUARDED": str(record)}


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def answering(port: int) -> bool:
    for _ in range(50):
        with socket.socket() as s:
            if s.connect_ex(("127.0.0.1", port)) == 0:
                return True
        time.sleep(0.1)
    return False


@pytest.mark.skipif(subprocess.run(["sudo", "-n", "-u", "nobody", "true"], capture_output=True).returncode != 0,
                    reason="needs sudo to run a listener as another user")
def test_refuses_a_port_another_user_is_listening_on(tmp_path):
    port = free_port()
    # sudo's own PATH finds the system python; this user's virtualenv is not readable by nobody.
    subprocess.Popen(["sudo", "-n", "-u", "nobody", "python3", "-I", "-c", LISTENER, str(port), MARK])
    try:
        assert answering(port)
        r = subprocess.run([CHROME_START], env={**os.environ, **assigned(tmp_path, port)},
                           capture_output=True, text=True, timeout=30)
    finally:
        subprocess.run(["sudo", "-n", "-u", "nobody", "pkill", "-f", MARK], capture_output=True)
    assert r.returncode != 0 and "held by another user" in r.stderr
    assert r.stdout == ""   # the other user's browser is not handed back as this agent's


def test_refuses_a_port_the_guard_is_not_protecting(tmp_path):
    r = subprocess.run([CHROME_START], env={**os.environ, **assigned(tmp_path, free_port(), guarded=False)},
                       capture_output=True, text=True, timeout=30)
    assert r.returncode != 0 and "port guard is not protecting" in r.stderr and r.stdout == ""


def test_uses_its_assigned_port_not_one_the_caller_names(tmp_path):
    """CHROME_CDP_PORT used to pick the port, which let a browser run on a port nothing restricts."""
    mine, named = free_port(), free_port()
    r = subprocess.run([CHROME_START], env={**os.environ, **assigned(tmp_path, mine, guarded=False), "CHROME_CDP_PORT": str(named)},
                       capture_output=True, text=True, timeout=30)
    assert f"ignoring CHROME_CDP_PORT={named}" in r.stderr and f"port {mine}" in r.stderr
