"""browser/setup: it tells the owner which running displays other users can still read.

setup installs to system paths, so it is not run whole. The script is sourced, which stops
before anything is installed, and the function it calls at the end is run on its own.
"""
import os
import pwd
import shutil
import subprocess
import time
from pathlib import Path

import pytest

SETUP = Path(__file__).parents[2] / "browser" / "setup"
ME = pwd.getpwuid(os.getuid()).pw_name
# A process named Xvfb that waits until its input closes. It starts nothing of its own.
STAND_IN = "#!/bin/sh\nread -r _\n"
OLD_ARGS = ["-auth", "/nonexistent/Xauthority", "-screen", "0", "1920x1080x24", "-nolisten", "tcp"]
NEW_ARGS = ["-auth", "/nonexistent/Xauthority", "-extension", "MIT-SHM", "-screen", "0", "1920x1080x24", "-nolisten", "tcp"]


def listing(tmp_path, *proc: str) -> subprocess.CompletedProcess:
    """What setup's listing prints. The path holds only what the listing needs: setup's
    installing steps could not run from it even if sourcing stopped stopping short of them."""
    tools = tmp_path / "tools"
    tools.mkdir(exist_ok=True)
    for tool in ("dirname", "id", "stat"):
        if not (tools / tool).exists():
            (tools / tool).symlink_to(shutil.which(tool))
    return subprocess.run(["/bin/bash", "-c", 'source "$1"; shift; list_open_displays "$@"', "_", str(SETUP), *proc],
                          env={"PATH": str(tools)}, capture_output=True, text=True, timeout=30)


@pytest.fixture
def stand_in(tmp_path):
    """Start a stand-in display server with the given arguments; gives back its pid."""
    exe = tmp_path / "Xvfb"
    exe.write_text(STAND_IN)
    exe.chmod(0o755)
    started = []

    def start(*args: str) -> int:
        p = subprocess.Popen([str(exe), *args], stdin=subprocess.PIPE)
        started.append(p)
        for _ in range(50):
            if Path(f"/proc/{p.pid}/comm").read_text().strip() == "Xvfb":
                return p.pid
            time.sleep(0.1)
        pytest.fail("the stand-in display server did not start")

    yield start
    for p in started:
        p.kill()
        p.wait()


def fake_process(proc: Path, pid: int, comm: str, *argv: str) -> None:
    d = proc / str(pid)
    d.mkdir(parents=True)
    (d / "comm").write_text(comm + "\n")
    (d / "cmdline").write_bytes(b"".join(a.encode() + b"\0" for a in argv))


def test_a_running_display_without_the_flag_is_named_with_its_user_and_the_fix(tmp_path, stand_in):
    pid = stand_in(":4391", *OLD_ARGS)
    r = listing(tmp_path)
    mine = [line for line in r.stdout.splitlines() if f"pid {pid})" in line or f"kill {pid}," in line]
    assert mine == [
        f"setup: display :4391 of {ME} (Xvfb, pid {pid}) puts the screen in shared memory that other users can read",
        f"setup:   to fix, as {ME}: close Chrome, run: kill {pid}, then chrome-start again",
    ], r.stdout + r.stderr
    assert r.returncode == 0


def test_a_running_display_with_the_flag_is_not_listed(tmp_path, stand_in):
    pid = stand_in(":4392", *NEW_ARGS)
    r = listing(tmp_path)
    assert r.returncode == 0 and r.stderr == ""
    assert str(pid) not in r.stdout and ":4392" not in r.stdout


def test_nothing_is_printed_when_no_display_server_runs(tmp_path):
    proc = tmp_path / "proc"
    fake_process(proc, 100, "bash", "bash")
    # Not an Xvfb: a search for one, with the same words on its command line.
    fake_process(proc, 101, "pgrep", "pgrep", "-f", "Xvfb :99 -auth")
    r = listing(tmp_path, str(proc))
    assert (r.returncode, r.stdout, r.stderr) == (0, "", "")


def test_the_flag_counts_only_as_two_arguments_of_their_own(tmp_path):
    """The command line is read argument by argument, so the words inside another argument,
    or the two halves apart, do not make a display look safe."""
    proc = tmp_path / "proc"
    fake_process(proc, 200, "Xvfb", "Xvfb", ":70", *NEW_ARGS)
    fake_process(proc, 201, "Xvfb", "Xvfb", ":71", "-fp", "x -extension MIT-SHM x", "-nolisten", "tcp")
    fake_process(proc, 202, "Xvfb", "Xvfb", ":72", "-extension", "GLX", "-fp", "MIT-SHM")
    fake_process(proc, 203, "Xvfb", "Xvfb", "-nolisten", "tcp")
    # Exited: no command line left.
    fake_process(proc, 204, "Xvfb")
    r = listing(tmp_path, str(proc))
    assert r.returncode == 0 and r.stderr == ""
    assert [line.split(" puts ")[0] for line in r.stdout.splitlines()[::2]] == [
        f"setup: display :71 of {ME} (Xvfb, pid 201)",
        f"setup: display :72 of {ME} (Xvfb, pid 202)",
        f"setup: display :0 of {ME} (Xvfb, pid 203)",
    ]


def test_nothing_a_process_wrote_on_its_command_line_reaches_the_terminal(tmp_path):
    proc = tmp_path / "proc"
    fake_process(proc, 300, "Xvfb", "Xvfb", ":73\x1b[2J", "\x1b]0;owned\x07", "line\nsetup: all displays are fine")
    r = listing(tmp_path, str(proc))
    assert r.stdout.splitlines() == [
        f"setup: display :0 of {ME} (Xvfb, pid 300) puts the screen in shared memory that other users can read",
        f"setup:   to fix, as {ME}: close Chrome, run: kill 300, then chrome-start again",
    ]
