"""An agent must not be able to get the check stopped for lack of memory.

An agent can write its own password to a few small files and give each many thousands of
names with hard links: every name is a place the password was found. The check keeps a fixed
number of places for each login in each root and counts the rest, so what it holds does not
grow with what an agent makes. And once anything was found, no error after that may end the
run as "nothing was checked".
"""
import asyncio
import logging
import os
import subprocess
import sys

from test_leakcheck import ALERTS, setup

from credbroker import leakcheck
from credbroker.config import Leakcheck

LEAK, UNFINISHED = "A password is where an agent can read it", "The daily leak check did not finish"
FILES, LINKS, HEADROOM = 10, 15000, 56   # 150,000 names; MiB the run may add to what Python had mapped before it

DRIVER = r"""
import os, resource, sys
from credbroker import leakcheck
from credbroker.config import Agent, Config, Leakcheck, Mqtt
from credbroker.onepw import Credentials, Login, Website

tmp, files, links, headroom = sys.argv[1], *map(int, sys.argv[2:])
PW = {"assistant": "assistant-own-pw", "research": "research-own-pw"}
for name in PW:
    os.mkdir(f"{tmp}/{name}")
for i in range(files):
    with open(f"{tmp}/assistant/f{i}", "w") as f:
        f.write(PW["assistant"])
    for j in range(links):
        os.link(f"{tmp}/assistant/f{i}", f"{tmp}/assistant/f{i}-{j}")
with open(f"{tmp}/research/leak.jsonl", "w") as f:
    f.write("typed " + PW["research"])


class Vault:
    def __init__(self, agent, token):
        self.agent = agent

    async def logins(self, fresh=False):
        return [Login("a", "Example", (Website("https://x", "AnywhereOnWebsite"),))]

    async def credentials(self, login_id):
        return Credentials("alex", PW[self.agent], {})


class Vouch:
    def __init__(self, path):
        pass

    def alert(self, alert_id, severity, title, body):
        print("ALERT", title, "|", body.replace("\n", " / "), flush=True)


agents = {i: Agent(n, i, op_token_key="OP_" + n.upper()) for i, n in enumerate(PW, 1)}
leakcheck.config.load = lambda: Config(agents, Leakcheck(roots=(f"{tmp}/*",)), Mqtt())
import credbroker.secretstore as ss
ss.load_secrets = lambda: {"OP_ASSISTANT": "t", "OP_RESEARCH": "t"}
leakcheck.AgentVault, leakcheck.VouchApprovals, leakcheck.journal = Vault, Vouch, lambda: [b""]
with open("/proc/self/statm") as f:
    mapped = int(f.read().split()[0]) * resource.getpagesize()
limit = mapped + headroom * 2**20
resource.setrlimit(resource.RLIMIT_AS, (limit, limit))
sys.argv = ["credbroker-leakcheck"]
leakcheck.main()
"""


def test_many_names_for_one_agents_own_password_do_not_cost_another_agents_leak(tmp_path):
    """The check runs with its memory limited to a little more than Python had before it
    started. Holding 150,000 places does not fit; holding a fixed number does."""
    r = subprocess.run([sys.executable, "-c", DRIVER, str(tmp_path), str(FILES), str(LINKS), str(HEADROOM)],
                       capture_output=True, text=True, timeout=600, env={"MALLOC_ARENA_MAX": "1", "PATH": "/usr/bin:/bin"})
    subprocess.run(["rm", "-rf", str(tmp_path / "assistant")], check=True)
    alerts = [line for line in r.stdout.splitlines() if line.startswith("ALERT")]
    assert "MemoryError" not in r.stdout + r.stderr, "the check ran out of memory"
    assert r.returncode == leakcheck.EXIT_LEAK, r.stdout[-2000:] + r.stderr[-2000:]
    (alert,) = alerts
    assert alert.startswith("ALERT " + LEAK)
    assert f"research/Example (password) in {tmp_path}/research/leak.jsonl" in alert, "the other agent's leak is not in the alert"
    assert f"assistant: {FILES * (LINKS + 1)}, research: 1" in alert, "the totals do not count the places that were not kept"
    assert f"and {FILES * (LINKS + 1) + 1 - (alert.count(' / ') - 2)} more, see the log" in alert


def test_the_places_kept_for_one_login_in_one_root_are_limited_and_the_rest_counted(monkeypatch, tmp_path, caplog):
    (tmp_path / "orig").write_text("the password is long-enough-pw")
    n = leakcheck.KEEP + 30
    for i in range(n - 1):
        (tmp_path / f"name{i:03}").hardlink_to(tmp_path / "orig")
    published = setup(monkeypatch, Leakcheck(roots=(str(tmp_path),)), leakcheck.config.Mqtt(url="mqtt://broker.example"))
    seen = {}
    real = leakcheck._summary

    def summary(hits, *more):
        seen["kept"] = len(hits)
        return real(hits, *more)
    monkeypatch.setattr(leakcheck, "_summary", summary)
    assert asyncio.run(leakcheck.run()) == leakcheck.EXIT_LEAK
    assert seen["kept"] == leakcheck.KEEP, "every place was held in memory"
    body = ALERTS[0][3]
    assert f"in {n} place(s)" in body and f"research: {n}" in body
    assert published[0][1]["count"] == n
    logged = [r.getMessage() for r in caplog.records if "possible leak" in r.getMessage()]
    assert len(logged) == leakcheck.KEEP + 1
    assert f"research/Example (password) in 30 more place(s) under {tmp_path}" in logged[-1]


def test_a_roots_hits_are_logged_when_that_root_ends(monkeypatch, tmp_path, caplog):
    """Not after every root is done: a later root that stops the check must not cost them."""
    first, second = tmp_path / "a", tmp_path / "b"
    first.mkdir()
    second.mkdir()
    (first / "leak.jsonl").write_text("the password is long-enough-pw")
    (second / "file").write_text("x")
    setup(monkeypatch, Leakcheck(roots=(str(tmp_path / "*"),)))
    real, at_second = leakcheck._read, []

    def read(name, *a, **kw):
        if name == "file":
            at_second.append(caplog.text)
        return real(name, *a, **kw)
    monkeypatch.setattr(leakcheck, "_read", read)
    assert asyncio.run(leakcheck.run()) == leakcheck.EXIT_LEAK
    assert "possible leak: research/Example (password) in " + str(first / "leak.jsonl") in at_second[0]


def test_an_error_after_a_hit_was_found_still_tells_the_phone_of_the_leak(monkeypatch, tmp_path):
    (tmp_path / "leak.jsonl").write_text("the password is long-enough-pw")
    setup(monkeypatch, Leakcheck(roots=(str(tmp_path),)))

    def broken(*a):
        raise MemoryError
    monkeypatch.setattr(leakcheck, "_summary", broken)
    monkeypatch.setattr(sys, "argv", ["credbroker-leakcheck"])
    monkeypatch.setattr(leakcheck.os, "_exit", lambda c: (_ for _ in ()).throw(SystemExit(c)))
    code = None
    try:
        leakcheck.main()
    except SystemExit as e:
        code = e.code
    assert code == leakcheck.EXIT_FAILED   # the check did not do all it should: the unit shows as failed
    titles = [a[2] for a in ALERTS]
    assert titles == [LEAK, UNFINISHED]
    assert ALERTS[0][3] == leakcheck.FOUND_NOT_LISTED
    assert "nothing was checked" not in " ".join(a[3] for a in ALERTS)
    assert "MemoryError" in ALERTS[1][3] and "part of the way through" in ALERTS[1][3]


def test_an_error_after_the_files_were_read_never_says_nothing_was_checked(monkeypatch, tmp_path):
    (tmp_path / "clean.txt").write_text("nothing here")
    setup(monkeypatch, Leakcheck(roots=(str(tmp_path),)))

    def broken(*a, **kw):
        raise RuntimeError
    monkeypatch.setattr(leakcheck, "scan_chunks", broken)   # caught: the journal is named as not read
    monkeypatch.setattr(leakcheck, "_unfinished", broken)   # not caught by anything of its own
    monkeypatch.setattr(sys, "argv", ["credbroker-leakcheck"])
    monkeypatch.setattr(leakcheck.os, "_exit", lambda c: (_ for _ in ()).throw(SystemExit(c)))
    code = None
    try:
        leakcheck.main()
    except SystemExit as e:
        code = e.code
    assert code == leakcheck.EXIT_FAILED
    assert [a[2] for a in ALERTS] == [UNFINISHED]
    assert "nothing was checked" not in ALERTS[0][3] and "part of the way through" in ALERTS[0][3]


def test_an_error_between_two_roots_still_tells_the_phone_what_the_first_one_held(monkeypatch, tmp_path):
    """Not only after every root is done: the first root's leak was found, so the phone hears of it."""
    for name in ("a", "b"):
        (tmp_path / name).mkdir()
    (tmp_path / "a" / "leak.jsonl").write_text("the password is long-enough-pw")
    setup(monkeypatch, Leakcheck(roots=(str(tmp_path / "*"),)))
    real = leakcheck._log_places

    def log_then_break(hits):
        real(hits)
        if hits:
            raise RuntimeError
    monkeypatch.setattr(leakcheck, "_log_places", log_then_break)
    monkeypatch.setattr(sys, "argv", ["credbroker-leakcheck"])
    monkeypatch.setattr(leakcheck.os, "_exit", lambda c: (_ for _ in ()).throw(SystemExit(c)))
    code = None
    try:
        leakcheck.main()
    except SystemExit as e:
        code = e.code
    assert code == leakcheck.EXIT_FAILED
    assert [a[2] for a in ALERTS] == [LEAK, UNFINISHED] and ALERTS[0][3] == leakcheck.FOUND_NOT_LISTED
    assert "nothing was checked" not in ALERTS[1][3]


def test_a_place_held_is_cut_to_the_end_of_its_path(monkeypatch, tmp_path, caplog):
    """Folders nest without limit, so a fixed number of places is not a fixed amount of memory
    unless each place has a length limit too."""
    setup(monkeypatch, Leakcheck(roots=(str(tmp_path),)))
    fd = os.open(tmp_path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        for _ in range(60):   # 60 names of 200 characters: a path of 12,000 and more
            os.mkdir("d" * 200, dir_fd=fd)
            below = os.open("d" * 200, os.O_RDONLY | os.O_DIRECTORY, dir_fd=fd)
            os.close(fd)
            fd = below
        with open(os.open("bottom.txt", os.O_WRONLY | os.O_CREAT, 0o600, dir_fd=fd), "w") as f:
            f.write("the password is long-enough-pw")
    finally:
        os.close(fd)
    seen = {}
    real = leakcheck._summary

    def summary(hits, *more):
        seen["where"] = [h.where for h in hits]
        return real(hits, *more)
    monkeypatch.setattr(leakcheck, "_summary", summary)
    try:
        assert asyncio.run(leakcheck.run()) == leakcheck.EXIT_LEAK
    finally:
        subprocess.run(["rm", "-rf", str(tmp_path / ("d" * 200))], check=True)
    (where,) = seen["where"]
    assert len(where) == leakcheck.WHERE_LEN and where.startswith("...") and where.endswith("/bottom.txt")
    assert max(len(r.getMessage()) for r in caplog.records) < leakcheck.WHERE_LEN + 200


def test_each_root_is_named_in_the_log_as_it_starts(monkeypatch, tmp_path, caplog):
    """A run that is killed leaves no last word. The line before it says whose folder was being read."""
    first, second = tmp_path / "a", tmp_path / "b"
    for root in (first, second):
        root.mkdir()
        (root / "leak.jsonl").write_text("the password is long-enough-pw")
    setup(monkeypatch, Leakcheck(roots=(str(tmp_path / "*"),)))
    caplog.set_level(logging.INFO)
    opened = []
    real = leakcheck.scan

    def scan(roots, *a, **kw):
        opened.append(caplog.text)   # what the log held when this root was about to be opened
        return real(roots, *a, **kw)
    monkeypatch.setattr(leakcheck, "scan", scan)
    assert asyncio.run(leakcheck.run()) == leakcheck.EXIT_LEAK
    for root, before in zip((first, second), opened, strict=True):
        assert f"leak check: searching {str(root)!r}" in before, "the root was opened before it was named in the log"
    lines = caplog.text.splitlines()
    for root in (first, second):
        started = next(i for i, line in enumerate(lines) if f"searching {str(root)!r}" in line)
        hit = next(i for i, line in enumerate(lines) if f"possible leak: research/Example (password) in {root}" in line)
        assert started < hit
