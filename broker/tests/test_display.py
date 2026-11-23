"""browser/chrome-start: the virtual display belongs to the agent alone.

Chrome is replaced by a stub that answers on the DevTools port, so only the display
handling is under test.
"""
import os
import pwd
import shutil
import socket
import subprocess
import time
from pathlib import Path

import pytest
from test_chrome_start import assigned

X_SOCKETS = "/tmp/.X11-unix"  # noqa: S108 - where X servers listen, not a scratch file
CHROME_START = Path(__file__).parents[2] / "browser" / "chrome-start"
STUB_CHROME = """#!/bin/sh
for a in "$@"; do case "$a" in --remote-debugging-port=*) port="${a#*=}" ;; esac; done
printf '%s\\n' "$XAUTHORITY" > "$HOME/chrome-env"
exec python3 -I -c 'import http.server, sys
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.end_headers(); self.wfile.write(b"{}")
    def log_message(self, *a): pass
http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()' "$port"
"""
# Open the display the way any X client does and print the server's first byte:
# 1 is "welcome", 0 is "refused". argv: display number, then the key in hex if there is one.
CONNECT = """
import socket, struct, sys
key = bytes.fromhex(sys.argv[2]) if len(sys.argv) > 2 else b""
name = b"MIT-MAGIC-COOKIE-1" if key else b""
pad = lambda b: b + bytes(-len(b) % 4)
s = socket.socket(socket.AF_UNIX); s.settimeout(5)
s.connect("/tmp/.X11-unix/X" + sys.argv[1])
s.sendall(b"l\\0" + struct.pack("<HHHHH", 11, 0, len(name), len(key), 0) + pad(name) + pad(key))
print(s.recv(1)[0])
"""
# Open the display with its key and ask the server whether it has an extension. argv: display
# number, key in hex, extension name. Prints 1 if the server offers it, 0 if not.
HAS_EXTENSION = """
import socket, struct, sys
key, ext = bytes.fromhex(sys.argv[2]), sys.argv[3].encode()
name = b"MIT-MAGIC-COOKIE-1"
pad = lambda b: b + bytes(-len(b) % 4)
s = socket.socket(socket.AF_UNIX); s.settimeout(5)
s.connect("/tmp/.X11-unix/X" + sys.argv[1])
s.sendall(b"l\\0" + struct.pack("<HHHHH", 11, 0, len(name), len(key), 0) + pad(name) + pad(key))
def read(n):
    data = b""
    while len(data) < n:
        more = s.recv(n - len(data))
        if not more: sys.exit("the display closed the connection")
        data += more
    return data
head = read(8)
if head[0] != 1: sys.exit("the display refused the key")
read(4 * struct.unpack("<H", head[6:8])[0])
s.sendall(struct.pack("<BxHHxx", 98, 2 + len(pad(ext)) // 4, len(ext)) + pad(ext))
print(read(32)[8])
"""
# Chrome, when run by root, needs this to start at all.
ROOT_FLAGS = {"CHROME_EXTRA_FLAGS": "--no-sandbox"} if os.getuid() == 0 else {}

needs = pytest.mark.skipif(
    not (shutil.which("Xvfb") and shutil.which("xauth"))
    or subprocess.run(["sudo", "-n", "-u", "nobody", "true"], capture_output=True).returncode != 0,
    reason="needs Xvfb, xauth, and sudo to act as another user")


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def free_display() -> int:
    return next(n for n in range(700, 900) if not os.path.exists(f"{X_SOCKETS}/X{n}"))


def connect(display: int, *key: str, as_nobody: bool = False) -> str:
    cmd = ["python3", "-I", "-c", CONNECT, str(display), *key]
    r = subprocess.run((["sudo", "-n", "-u", "nobody"] if as_nobody else []) + cmd, capture_output=True, text=True, timeout=20)
    return r.stdout.strip() or r.stderr.strip()[-200:]


def scratch_env(tmp_path, display: int, port: int) -> tuple[dict[str, str], Path]:
    """A scratch home, and an environment in which chrome-start finds the stub Chrome first."""
    home, bin_dir = tmp_path / "home", tmp_path / "bin"
    home.mkdir(exist_ok=True), bin_dir.mkdir(exist_ok=True)
    stub = bin_dir / "google-chrome-stable"
    stub.write_text(STUB_CHROME)
    stub.chmod(0o755)
    env = {**os.environ, "HOME": str(home), "PATH": f"{bin_dir}:{os.environ['PATH']}",
           **assigned(tmp_path, port), "CHROME_DISPLAY": f":{display}"}
    env.pop("XAUTHORITY", None)
    return env, home


def chrome_start(tmp_path, display: int, port: int):
    """Run chrome-start in a scratch home, with the stub Chrome."""
    env, home = scratch_env(tmp_path, display, port)
    return subprocess.run([CHROME_START], env=env, capture_output=True, text=True, timeout=60), home


def key_of(keyfile: Path) -> str:
    return subprocess.run(["xauth", "-f", str(keyfile), "list"], capture_output=True, text=True).stdout.split()[-1]


def offers(display: int, keyfile: Path, extension: str) -> str:
    r = subprocess.run(["python3", "-I", "-c", HAS_EXTENSION, str(display), key_of(keyfile), extension],
                       capture_output=True, text=True, timeout=20)
    return r.stdout.strip() or r.stderr.strip()[-200:]


def shared_memory_others_can_attach(uid: int) -> list[str]:
    """This user's System V shared memory segments that have a group or other permission bit."""
    rows = [line.split() for line in Path("/proc/sysvipc/shm").read_text().splitlines()[1:]]
    return [f"id {r[1]} perms {r[2]} size {r[3]}" for r in rows if int(r[7]) == uid and int(r[2], 8) & 0o077]


def wait_for_display(display: int) -> None:
    for _ in range(50):
        if os.path.exists(f"{X_SOCKETS}/X{display}"):
            return
        time.sleep(0.1)
    pytest.fail("the test's own Xvfb did not start")


@pytest.fixture
def ids():
    display, port = free_display(), free_port()
    yield display, port
    for who in ([], ["sudo", "-n", "-u", "nobody"]):
        subprocess.run([*who, "pkill", "-f", f"Xvfb :{display} "], capture_output=True)
    subprocess.run(["pkill", "-f", f"serve_forever.* {port}$"], capture_output=True)


@pytest.fixture
def started(tmp_path, ids):
    display, port = ids
    r, home = chrome_start(tmp_path, display, port)
    return r, home, display


@needs
def test_another_user_cannot_open_the_agents_display(started):
    r, home, display = started
    assert r.returncode == 0, r.stderr
    assert connect(display, as_nobody=True) == "0"   # refused: they have no key


@needs
def test_the_agent_and_its_chrome_can(started):
    r, home, display = started
    assert r.returncode == 0, r.stderr
    keyfile = home / ".vouch-browser" / "Xauthority"
    assert (keyfile.stat().st_mode & 0o777, keyfile.parent.stat().st_mode & 0o777) == (0o600, 0o700)
    assert (home / "chrome-env").read_text().strip() == str(keyfile)   # Chrome was given the key
    key = subprocess.run(["xauth", "-f", str(keyfile), "list"], capture_output=True, text=True).stdout.split()[-1]
    assert connect(display, key) == "1"
    assert connect(display) == "0"   # even this user, without the key


@needs
def test_refuses_a_display_another_user_runs(tmp_path, ids):
    """Whoever runs the display server sees the screen and can type into it."""
    display, port = ids
    subprocess.Popen(["sudo", "-n", "-u", "nobody", "Xvfb", f":{display}", "-screen", "0", "640x480x24", "-nolisten", "tcp"],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    wait_for_display(display)
    r, home = chrome_start(tmp_path, display, port)
    # Named by its own uid: the refusal is about the server, not the sudo that launched it.
    assert r.returncode != 0 and f"run by another user (uid {pwd.getpwnam('nobody').pw_uid})" in r.stderr
    assert not (home / "chrome-env").exists()   # Chrome was never started on it


@needs
def test_a_process_that_only_names_the_display_is_not_its_server(tmp_path, ids):
    """Any user can put any words on a command line. Only a running Xvfb counts as the display."""
    display, port = ids
    decoy = subprocess.Popen(["sudo", "-n", "-u", "nobody", "python3", "-I", "-c", "import time; time.sleep(60)",
                              "Xvfb", f":{display}", "decoy"])
    try:
        time.sleep(0.5)
        r, home = chrome_start(tmp_path, display, port)
    finally:
        subprocess.run(["sudo", "-n", "-u", "nobody", "pkill", "-f", f"Xvfb :{display} decoy"], capture_output=True)
        decoy.wait(timeout=10)
    assert r.returncode == 0, r.stderr
    assert connect(display, as_nobody=True) == "0"   # and the display it started has a key


@needs
def test_replaces_its_own_display_that_has_no_key(tmp_path, ids):
    """A display left by an older chrome-start, with no browser on it, is restarted with a key."""
    display, port = ids
    subprocess.Popen(["Xvfb", f":{display}", "-screen", "0", "640x480x24", "-nolisten", "tcp"],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    wait_for_display(display)
    assert connect(display, as_nobody=True) == "1"   # open to anyone, as before
    r, home = chrome_start(tmp_path, display, port)
    assert r.returncode == 0, r.stderr
    assert connect(display, as_nobody=True) == "0"


@needs
def test_the_key_is_never_on_a_command_line(tmp_path, ids, monkeypatch):
    """Every user can read every command line in /proc, so a key passed as an argument is public."""
    display, port = ids
    seen = tmp_path / "argv"
    shims = tmp_path / "shims"
    shims.mkdir()
    for tool in ("xauth", "Xvfb"):
        shim = shims / tool
        shim.write_text(f'#!/bin/sh\nprintf \'%s\\n\' "$*" >> "{seen}"\nexec {shutil.which(tool)} "$@"\n')
        shim.chmod(0o755)
    monkeypatch.setenv("PATH", f"{shims}:{os.environ['PATH']}")
    r, home = chrome_start(tmp_path, display, port)
    assert r.returncode == 0, r.stderr
    keyfile = home / ".vouch-browser" / "Xauthority"
    key = subprocess.run(["xauth", "-f", str(keyfile), "list"], capture_output=True, text=True).stdout.split()[-1]
    assert len(key) == 32 and connect(display, key) == "1"   # the key works, so this is the real one
    assert str(keyfile) in seen.read_text()   # the recorders did run
    assert key not in seen.read_text()


@needs
def test_the_display_does_not_offer_shared_memory_frames(started):
    """With MIT-SHM, Chrome puts each frame in a segment any user can attach, key or no key."""
    r, home, display = started
    assert r.returncode == 0, r.stderr
    keyfile = home / ".vouch-browser" / "Xauthority"
    assert offers(display, keyfile, "BIG-REQUESTS") == "1"   # the question itself works
    assert offers(display, keyfile, "MIT-SHM") == "0", "the display offers MIT-SHM, so the screen is in memory any user can read"


@needs
def test_replaces_its_own_display_that_offers_shared_memory_frames(tmp_path, ids):
    """A display left by an older chrome-start has a key but still offers MIT-SHM."""
    display, port = ids
    keyfile = tmp_path / "home" / ".vouch-browser" / "Xauthority"
    keyfile.parent.mkdir(parents=True)
    subprocess.run(["xauth", "-q", "-f", str(keyfile), "source", "-"], input=f"add :{display} . {'ab' * 16}\n",
                   text=True, check=True, capture_output=True)
    old = subprocess.Popen(["Xvfb", f":{display}", "-auth", str(keyfile), "-screen", "0", "640x480x24", "-nolisten", "tcp"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    wait_for_display(display)
    assert offers(display, keyfile, "MIT-SHM") == "1"   # as an older chrome-start left it
    r, home = chrome_start(tmp_path, display, port)
    assert r.returncode == 0, r.stderr
    assert offers(display, keyfile, "MIT-SHM") == "0", "the old display, which offers MIT-SHM, is still the one in use"
    assert old.wait(timeout=10) is not None   # the old server was stopped, not left running


@pytest.mark.skipif(not (shutil.which("Xvfb") and shutil.which("xauth") and shutil.which("google-chrome-stable")),
                    reason="needs Xvfb, xauth and google-chrome-stable: only a real Chrome makes the segments")
def test_chrome_leaves_no_shared_memory_another_user_can_attach(tmp_path, ids):
    """Chrome's frames went into System V segments with mode 606: any user could attach and read the screen."""
    display, port = ids
    before = set(shared_memory_others_can_attach(os.getuid()))
    env, home = scratch_env(tmp_path, display, port)
    (tmp_path / "bin" / "google-chrome-stable").unlink()   # the real Chrome this time
    profile = home / ".vouch-browser" / "profile"
    try:
        r = subprocess.run([CHROME_START], env={**env, **ROOT_FLAGS}, capture_output=True, text=True, timeout=90)
        assert r.returncode == 0, r.stderr
        assert '"Browser"' in r.stdout   # a real Chrome answered
        mine: list[str] = []
        for _ in range(100):   # Chrome makes them as it draws its first frames
            mine = sorted(set(shared_memory_others_can_attach(os.getuid())) - before)
            if mine:
                break
            time.sleep(0.1)
    finally:
        subprocess.run(["pkill", "-f", f"--user-data-dir={profile}"], capture_output=True)
    assert mine == [], f"Chrome's screen is in shared memory other users can attach: {mine}"


@needs
def test_the_key_file_is_never_empty_while_the_key_is_written(tmp_path, ids, monkeypatch):
    """A display server reads its key file again when it changes, and an empty one lets any user in."""
    display, port = ids
    keyfile = tmp_path / "home" / ".vouch-browser" / "Xauthority"
    seen = tmp_path / "keyfile-state"
    shims = tmp_path / "shims"
    shims.mkdir()
    shim = shims / "xauth"
    shim.write_text(f'#!/bin/sh\nif [ -e "{keyfile}" ] && [ ! -s "{keyfile}" ]; then echo empty; else echo ok; fi >> "{seen}"\n'
                    f'exec {shutil.which("xauth")} "$@"\n')
    shim.chmod(0o755)
    monkeypatch.setenv("PATH", f"{shims}:{os.environ['PATH']}")
    r, home = chrome_start(tmp_path, display, port)
    assert r.returncode == 0, r.stderr
    assert seen.read_text().split() == ["ok"], "the key file was at its path with nothing in it while the key was being made"
    assert keyfile.stat().st_mode & 0o777 == 0o600 and connect(display, key_of(keyfile)) == "1"
    assert sorted(p.name for p in keyfile.parent.iterdir() if p.name.startswith("Xauthority")) == ["Xauthority"]   # nothing left behind


@needs
def test_two_runs_at_once_start_one_display(tmp_path, ids, monkeypatch):
    """Two runs that both found no display each made a key and a server, one over the other's."""
    display, port = ids
    started = tmp_path / "xvfb-starts"
    shims = tmp_path / "shims"
    shims.mkdir()
    # A slow xauth holds each run inside the step that makes the key, so the runs overlap.
    (shims / "xauth").write_text(f'#!/bin/sh\nsleep 1\nexec {shutil.which("xauth")} "$@"\n')
    (shims / "Xvfb").write_text(f'#!/bin/sh\necho started >> "{started}"\nexec {shutil.which("Xvfb")} "$@"\n')
    for shim in shims.iterdir():
        shim.chmod(0o755)
    monkeypatch.setenv("PATH", f"{shims}:{os.environ['PATH']}")
    env, home = scratch_env(tmp_path, display, port)
    runs = [subprocess.Popen([CHROME_START], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) for _ in range(2)]
    results = [(p.communicate(timeout=90), p.returncode) for p in runs]
    assert [code for _, code in results] == [0, 0], [err for (_, err), _ in results]
    assert started.read_text().split() == ["started"], "both runs started a display server on the same display"
    keyfile = home / ".vouch-browser" / "Xauthority"
    assert connect(display, key_of(keyfile)) == "1"
    assert connect(display, as_nobody=True) == "0"


@needs
def test_warns_while_chrome_is_still_on_a_display_that_offers_shared_memory_frames(tmp_path, ids):
    """Stopping the display would take the running browser with it, so the user is told instead."""
    display, port = ids
    keyfile = tmp_path / "home" / ".vouch-browser" / "Xauthority"
    keyfile.parent.mkdir(parents=True)
    subprocess.run(["xauth", "-q", "-f", str(keyfile), "source", "-"], input=f"add :{display} . {'ab' * 16}\n",
                   text=True, check=True, capture_output=True)
    old = subprocess.Popen(["Xvfb", f":{display}", "-auth", str(keyfile), "-screen", "0", "640x480x24", "-nolisten", "tcp"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    wait_for_display(display)
    first, _ = chrome_start(tmp_path, display, port)   # replaces the display and leaves the stub Chrome answering
    assert first.returncode == 0 and old.wait(timeout=10) is not None
    subprocess.run(["pkill", "-f", f"Xvfb :{display} "], capture_output=True)
    again = subprocess.Popen(["Xvfb", f":{display}", "-auth", str(keyfile), "-screen", "0", "640x480x24", "-nolisten", "tcp"],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        if offers(display, keyfile, "MIT-SHM") == "1":
            break
        time.sleep(0.1)
    r, _ = chrome_start(tmp_path, display, port)
    assert r.returncode == 0 and "puts the screen in shared memory that other users can read" in r.stderr, r.stderr
    assert f"kill {again.pid}" in r.stderr and again.poll() is None   # told how to fix it; the display is left running
