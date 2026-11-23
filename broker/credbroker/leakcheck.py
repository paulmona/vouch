"""Daily check that no vault secret has turned up where it should never be.

Runs as root (it must read every agent's home), loads each agent's 1Password
logins with the broker's own Vault AppRole, and searches the configured roots
(by default agent transcripts and config in ~/.claude, and the broker's
database) and the broker's journal for each password and security answer
(Concealed field), raw and JSON-escaped. Secrets are held in memory only. A
match is logged as an error naming the login and the file, never the matched
text; the owner's phones are alerted through Vouch, then an MQTT event is
published when MQTT is configured, and the check exits 3. What was found in a
root is logged when that root is done, and the journal is read in pieces, so
nothing a later step does keeps a file's match out of the log. At most KEEP
places are held for each secret in each root, each cut to the end of its path,
and the rest are counted, so what the check holds does not grow with the number
of names an agent gives a file or with how deep it puts them.
Once it has started on the files, an error never ends the run as "nothing was checked":
the owner is told that a secret was found (if one was) and that the check did
not finish. The unit has a memory limit, and whatever ends it as failed starts
credbroker-leakcheck-failed.service, which sends a fixed alert of its own.

The files it reads belong to the agents it is checking, so it trusts nothing
about them: it never follows a symbolic link an agent could have made (only one
in a folder that root owns and nobody else can write to), reads only regular files, opens
everything relative to a directory it already holds open (so a link swapped in
while it looks leads nowhere), holds only a few directories open however deep
they are nested, stays on the root's own filesystem, and gives up after
SCAN_TIMEOUT. That time is shared out between the roots, so one agent's files
cannot use up another's: a root that runs out, cannot be opened or fails in any
other way is named, and what was found elsewhere is still reported. A check that
crashed, did not finish or had nowhere to look exits 1 and alerts the owner too,
so a stalled check is not mistaken for a clean one.
"""
from __future__ import annotations

import asyncio
import errno
import glob
import json
import logging
import os
import select
import stat
import subprocess
import sys
import threading
import time
from collections import Counter
from collections.abc import Iterable, Iterator
from dataclasses import dataclass, field
from itertools import zip_longest
from pathlib import Path

from . import config, events
from .approval import ApprovalError, VouchApprovals
from .onepw import AgentVault, OnePasswordError

log = logging.getLogger("credbroker.leakcheck")

SKIP_DIRS = {"chrome-profile", "node_modules", ".venv", ".git", "cache", ".cache", "plugins"}
MAX_FILE = 64 * 2**20
MIN_LEN = 6  # shorter values match ordinary text too often to mean anything
MAX_PLACES = 20  # in the MQTT event and the alert
WHERE_LEN = 4096  # characters of one place that are held and logged: its end. Folders nest without limit, so a path has no length limit of its own
KEEP = 200  # places held for one login in one root; the rest are counted. An agent can make as many places as it likes
PLACE_LEN = 150  # characters of one place there: an agent chooses its file names, and one long one must not fill the alert
MAX_AGENTS = 12  # agents whose totals open the alert
ALERT_LEN = 2000  # Vouch cuts an alert's text here; the alert is built to fit, so its last line is never lost
JOURNAL_TIMEOUT = 120  # seconds for journalctl to hand over the broker's journal
SCAN_TIMEOUT = 20 * 60  # seconds for all roots together; the unit's own timeout is longer, so this one gets to alert
GRACE = 5  # seconds a root gets to notice its time is up before its thread is left behind
EXIT_LEAK = 3    # not 1: that is what an uncaught error exits with, and the two must not look alike
EXIT_FAILED = 1
LEAK_TITLE = "A password is where an agent can read it"
FOUND_NOT_LISTED = ("The daily check found a password or security answer where an agent can read it, and then stopped "
                    "before it could list the places. Change it, then find out how it got there. The places are in "
                    "the log: journalctl -u credbroker-leakcheck")
OUT_OF = (errno.EMFILE, errno.ENFILE, errno.ENOMEM)  # the check's own trouble, not something odd about one file


class NotSearched(Exception):
    """A place to search could not be opened as the folder it should be."""


@dataclass(frozen=True)
class Secret:
    agent: str
    login: str
    kind: str  # password | answer
    value: str = field(repr=False)

    def needles(self) -> set[bytes]:
        raw = self.value.encode()
        escaped = json.dumps(self.value)[1:-1].encode()
        return {raw, escaped}


@dataclass(frozen=True)
class Hit:
    secret: Secret
    where: str


def scan_bytes(data: bytes, secrets: list[Secret]) -> list[Secret]:
    return [s for s in secrets if any(n in data for n in s.needles())]


def scan_chunks(chunks: Iterable[bytes], secrets: list[Secret], found: list[Secret] | None = None) -> list[Secret]:
    """`scan_bytes` over data that arrives in pieces, holding one piece at a time. The end of each
    piece is kept and searched again with the next: one byte less than the longest thing looked
    for, so a secret split between two pieces is found. Secrets are added to `found` as they
    turn up, so a caller keeps them if the pieces stop with an error."""
    found = [] if found is None else found
    keep = max((len(n) for s in secrets for n in s.needles()), default=1) - 1
    tail = b""
    for chunk in chunks:
        data = tail + chunk
        found += [s for s in scan_bytes(data, secrets) if s not in found]
        tail = data[max(len(data) - keep, 0):]
    return found


def _read(name: str, dir_fd: int | None = None, dev: int | None = None) -> bytes | None:
    """The contents of a regular file of a sane size, or None. Never follows a link, never blocks on a pipe.
    `name` is looked up in the open directory `dir_fd`; `dev` is the filesystem it must be on."""
    try:
        fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC, dir_fd=dir_fd)
    except OSError as e:
        if e.errno in OUT_OF:
            raise
        return None
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode) or st.st_size > MAX_FILE or dev not in (None, st.st_dev):
            return None
        chunks, left = [], MAX_FILE + 1   # the size can be a lie (/proc) or change under us
        while left > 0 and (chunk := os.read(fd, min(left, 2**20))):
            chunks.append(chunk)
            left -= len(chunk)
        return None if left <= 0 else b"".join(chunks)
    except OSError:
        return None
    finally:
        os.close(fd)


def _open_root(root: Path) -> int | None:
    """An open descriptor for the directory `root`, or None. The path is walked one name at a
    time, and a link is followed only where nobody but root could have put it: in a directory
    that root owns and no one else can write to. Below an agent's home, no link is followed."""
    fd = os.open("/", os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
    try:
        for part in Path(os.path.abspath(root)).parts[1:]:
            parent = os.fstat(fd)
            roots_own = parent.st_uid == 0 and not parent.st_mode & 0o022
            below = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NONBLOCK | os.O_CLOEXEC
                            | (0 if roots_own else os.O_NOFOLLOW), dir_fd=fd)
            os.close(fd)
            fd = below
    except OSError:
        os.close(fd)
        return None
    return fd


DIR_FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC


def _enter(parent: int, name: str, dev: int) -> int | None:
    """Open the folder `name` inside the open folder `parent`, or None if it is not a folder
    there any more, is a link, or is on another filesystem."""
    try:
        fd = os.open(name, DIR_FLAGS, dir_fd=parent)
    except OSError as e:
        if e.errno in OUT_OF:
            raise
        return None
    if os.fstat(fd).st_dev != dev:
        os.close(fd)
        return None
    return fd


def _names(node: tuple) -> list[str]:
    names = []
    while node[0] is not None:
        names.append(node[1])
        node = node[0]
    return names[::-1]


def _files(root: Path, must_open: bool = False):
    """(path, contents or None) for each file under `root`, and (path, None) for each folder.
    Every folder and file is opened by name inside a folder already held open, never by its
    full path and never through `..`, so a folder swapped for a link or moved while this runs
    leads nowhere outside the root. A filesystem mounted inside the root is not entered.

    Only the root and the folder being listed are held open, however deep the folders go. The
    folders still to list are remembered by name. One that is not inside the folder just
    listed is reached again from the root, name by name, the same way."""
    top = _open_root(root)
    if top is None:
        if must_open:
            raise NotSearched
        log.warning("leak check: %r is not a directory, or is reached through a symbolic link; not searched", str(root))
        return
    here = None                    # the folder being listed, and which one that is
    at: tuple | None = None
    try:
        dev = os.fstat(top).st_dev
        todo: list[tuple] = [(None, "")]   # (the folder it is in, its name); the first is the root itself
        while todo:
            node = todo.pop()
            names = _names(node)
            path = os.path.normpath(os.path.join(root, *names))
            yield path, None
            if here is not None and node[0] is at:
                fd = _enter(here, node[1], dev)
            else:
                fd = os.open(".", DIR_FLAGS, dir_fd=top)
                for name in names:
                    below = _enter(fd, name, dev)
                    os.close(fd)
                    fd = below
                    if fd is None:
                        break
            if here is not None:
                os.close(here)
            here, at = fd, node
            if fd is None:
                continue
            inside = []
            with os.scandir(fd) as entries:
                for e in entries:
                    try:
                        folder = e.is_dir(follow_symlinks=False)
                    except OSError:
                        folder = False
                    if not folder:
                        yield os.path.join(path, e.name), _read(e.name, fd, dev)
                    elif e.name not in SKIP_DIRS:
                        inside.append(e.name)
            todo += [(node, name) for name in reversed(inside)]
    finally:
        if here is not None:
            os.close(here)
        os.close(top)


def scan(roots: list[Path], secrets: list[Secret], hits: list[Hit] | None = None,
         deadline: float | None = None, must_open: bool = False,
         more: Counter[Secret] | None = None) -> tuple[list[Hit], int]:
    """Hits are added to `hits` as they are found, so a caller that stops waiting keeps them.
    At most KEEP are held for each secret, each cut to the last WHERE_LEN characters of its
    path; any after that are counted in `more`. So what is held does not grow with the number
    of files an agent makes or with how deep it puts them.
    Raises TimeoutError once `deadline` (on the monotonic clock) has passed: it is looked at
    for every folder as well as every file, so a tree of empty folders stops too. With
    `must_open`, raises NotSearched for a root that cannot be opened as a folder."""
    hits, files = [] if hits is None else hits, 0
    more = Counter() if more is None else more
    held = Counter(h.secret for h in hits)
    for root in roots:
        for p, data in _files(root, must_open):
            if deadline is not None and time.monotonic() > deadline:
                raise TimeoutError
            if data is None:
                continue
            files += 1
            for s in scan_bytes(data, secrets):
                if held[s] < KEEP:
                    held[s] += 1
                    hits.append(Hit(s, p if len(p) <= WHERE_LEN else "..." + p[3 - WHERE_LEN:]))
                else:
                    more[s] += 1
    return hits, files


async def scan_each(roots: list[Path], secrets: list[Secret], hits: list[Hit] | None = None,
                    unfinished: list[str] | None = None,
                    more: Counter[Secret] | None = None) -> tuple[list[Hit], int, list[str], Counter[Secret]]:
    """Scan every root within SCAN_TIMEOUT in all, each within an equal share of what is left.
    Returns the hits held (at most KEEP for each secret in each root), the number of files
    read, the roots that were not fully searched (out of time, not a folder that can be
    opened, or stopped by any error), and for each secret how many more places it was found
    in. Whatever happens in one root, what it had found is kept, it is logged as soon as that
    root ends, and the next root is still searched. `hits`, `unfinished` and `more` are added to
    as it goes, so a caller that passes its own still has them if this raises."""
    hits, unfinished = [] if hits is None else hits, [] if unfinished is None else unfinished
    more, files = Counter() if more is None else more, 0
    end = time.monotonic() + SCAN_TIMEOUT
    for i, root in enumerate(roots):
        share = max(end - time.monotonic(), 0) / (len(roots) - i)
        found: list[Hit] = []
        uncounted: Counter[Secret] = Counter()
        log.info("leak check: searching %r", str(root))   # a run that is killed says nothing more: this is its last word
        try:
            files += (await asyncio.wait_for(
                _detached(scan, [root], secrets, found, time.monotonic() + share, True, uncounted), share + GRACE))[1]
        except TimeoutError:
            unfinished.append(str(root))
        except NotSearched:
            unfinished.append(f"{root} (not a folder, or reached through a symbolic link)")
        except Exception as e:  # noqa: BLE001 - whatever one agent's files did, the others are still checked
            log.warning("leak check: stopped in %r: %s", str(root), type(e).__name__)
            unfinished.append(f"{root} ({type(e).__name__})")
        found, uncounted = list(found), Counter(uncounted)   # a thread left behind may still be adding to its own
        hits += found   # before they are logged: if logging stops the check, the caller knows of them
        more.update(uncounted)
        _log_places(found)
        for s, n in sorted(uncounted.items(), key=lambda sn: (sn[0].agent, sn[0].login, sn[0].kind)):
            log.error("possible leak: %s", _line(f"{s.agent}/{s.login} ({s.kind}) in {n} more place(s) under {root}"))
    return hits, files, unfinished, more


def _detached(fn, *args) -> asyncio.Future:
    """Run `fn` in a thread nothing waits for. asyncio's own thread pool is joined when the
    loop closes, so one read that never returns would hold the whole check open."""
    loop = asyncio.get_running_loop()
    fut = loop.create_future()

    def settle(setter, value):
        if not fut.done():
            setter(value)

    def work():
        try:
            result = fn(*args)
        except Exception as e:  # noqa: BLE001 - handed to whoever awaits the future
            loop.call_soon_threadsafe(settle, fut.set_exception, e)
        else:
            loop.call_soon_threadsafe(settle, fut.set_result, result)
    threading.Thread(target=work, daemon=True).start()
    return fut


def _line(text: str) -> str:
    """`text` as one line of a report. An agent chooses its own file names, and a line break or
    a terminal control code in one must not look like a second line of the report."""
    return "".join(c if c.isprintable() else "?" for c in text)


def _plant(path: str, text: str) -> tuple[int, str, int]:
    """Write the canary as a new file, and return what `_unplant` needs to remove that file
    and no other. The folder may belong to an agent, so it is opened the way a root to search
    is (no link an agent could have made is followed), and the file is made and removed by
    name inside that open folder: a link at this path, or in place of the folder, sends root
    nowhere."""
    parent, name = os.path.split(os.path.abspath(path))
    dir_fd = _open_root(Path(parent))
    if dir_fd is None:
        raise SystemExit("credbroker-leakcheck: the folder of leakcheck.canary_file is missing, "
                         "or is reached through a symbolic link")
    try:
        try:
            os.unlink(name, dir_fd=dir_fd)
        except FileNotFoundError:
            pass
        fd = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600, dir_fd=dir_fd)
    except OSError:
        os.close(dir_fd)
        raise
    os.write(fd, text.encode())
    return dir_fd, name, fd


def _unplant(dir_fd: int, name: str, fd: int) -> None:
    """`fd` is the canary, held open since it was written so that its inode number cannot be
    given to another file: the name is removed only if it is still that file."""
    try:
        made, st = os.fstat(fd), os.stat(name, dir_fd=dir_fd, follow_symlinks=False)
        if (st.st_dev, st.st_ino) == (made.st_dev, made.st_ino):
            os.unlink(name, dir_fd=dir_fd)
    except OSError:
        pass
    finally:
        os.close(fd)
        os.close(dir_fd)


def _alert(title: str, body: str) -> None:
    try:
        VouchApprovals(config.VOUCH_SOCKET).alert("leak_" + os.urandom(9).hex(), "critical", title, body)
    except ApprovalError as e:
        log.warning("could not alert the owner's phone: %s", e)
    except Exception as e:  # noqa: BLE001 - an alert that cannot be sent must not stop the ones after it
        log.warning("could not alert the owner's phone: %s", type(e).__name__)


def journal() -> Iterator[bytes]:
    """The broker's journal of the last two days, a piece at a time: the broker logs a line for
    each request an agent makes, so an agent can make it as large as it likes. Raises if
    journalctl is not done within JOURNAL_TIMEOUT or does not exit 0."""
    argv = ["journalctl", "-u", "credbroker", "--since", "-2d", "-o", "cat", "--no-pager"]
    end = time.monotonic() + JOURNAL_TIMEOUT
    with subprocess.Popen(argv, stdout=subprocess.PIPE) as p:  # noqa: S603 - fixed argv, journalctl on PATH
        try:
            while True:
                left = end - time.monotonic()
                if left <= 0 or not select.select([p.stdout], [], [], left)[0]:
                    raise subprocess.TimeoutExpired(argv, JOURNAL_TIMEOUT)
                chunk = os.read(p.stdout.fileno(), 2**20)
                if not chunk:
                    break
                yield chunk
            if p.wait(max(end - time.monotonic(), 0)):
                raise subprocess.CalledProcessError(p.returncode, argv)
        finally:
            p.kill()


async def load(agents, secrets_env: dict[str, str], unread: list[tuple[str, str]] | None = None) -> tuple[list[Secret], int]:
    """A login that 1Password would not hand over is added to `unread` as (agent, title): it
    was not checked."""
    out, short = [], 0
    for a in agents.values():
        token = secrets_env.get(a.op_token_key or "")
        if not token:
            continue
        vault = AgentVault(a.name, token)
        for login in await vault.logins(fresh=True):
            try:
                creds = await vault.credentials(login.id)
            except OnePasswordError:
                if unread is not None:
                    unread.append((a.name, login.title))
                continue
            values = [("password", creds.password)] + [("answer", v) for v in creds.extras.values()]
            for kind, v in values:
                if len(v) < MIN_LEN:
                    short += 1
                else:
                    out.append(Secret(a.name, login.title, kind, v))
    return out, short


def _place(h: Hit, short: bool = False) -> str:
    """One hit as one line. With `short`, at most PLACE_LEN characters: a long login title
    loses its end and a long path its start, because the end of a path is the file."""
    login, where = h.secret.login, h.where
    if short:
        login = login if len(login) <= 40 else login[:37] + "..."
        room = max(PLACE_LEN - len(f"{h.secret.agent}/{login} ({h.secret.kind}) in "), 3)
        where = where if len(where) <= room else "..." + where[len(where) - (room - 3):]
    line = _line(f"{h.secret.agent}/{login} ({h.secret.kind}) in {where}")
    return line[:PLACE_LEN] if short else line


def _log_places(hits: list[Hit]) -> None:
    for p in sorted({_place(h) for h in hits}):
        log.error("possible leak: %s", p)


def _summary(hits: list[Hit], more: Counter[Secret] | None = None) -> tuple[int, list[str], str]:
    """How many places there are, up to MAX_PLACES of them shortened, and the text of the
    alert. `more` is the places that were counted and not held. The places are taken from each
    agent in turn, so no agent's hits can take the room of another's. The alert opens with how
    many each agent has, and ends with how many places it left out. It never passes ALERT_LEN,
    so that last line is not cut off."""
    by_agent: dict[str, list[str]] = {}
    for _, agent, short in sorted({(_place(h), h.secret.agent, _place(h, short=True)) for h in hits}):
        by_agent.setdefault(agent, []).append(short)
    total = Counter({a: len(v) for a, v in by_agent.items()})
    for s, n in (more or {}).items():
        total[s.agent] += n
    count = sum(total.values())
    places = [p for turn in zip_longest(*by_agent.values()) for p in turn if p is not None][:MAX_PLACES]
    names = sorted(total)
    lines = [f"The daily check found a password or security answer in {count} place(s). Change it, then find out "
             "how it got there. Places per agent:",
             ", ".join(f"{_line(a)}: {total[a]}" for a in names[:MAX_AGENTS])
             + (f", and {len(names) - MAX_AGENTS} more agent(s)" if len(names) > MAX_AGENTS else "")]
    more = "and {} more, see the log: journalctl -u credbroker-leakcheck"
    for p in places:
        if len("\n".join([*lines, p, more.format(count)])) > ALERT_LEN:
            break
        lines.append(p)
    if count > len(lines) - 2:
        lines.append(more.format(count - (len(lines) - 2)))
    return count, places, "\n".join(lines)


def _unfinished(places: list[str]) -> str:
    """The text of the alert for a check that did not finish. It names every place, or as many
    as fit in MAX_PLACES lines and ALERT_LEN characters and then how many it left out. A long
    place keeps its start and its end. Only when every place is named does it say that
    everything else was checked."""
    half = (PLACE_LEN - 3) // 2
    places = [p if len(p) <= PLACE_LEN else p[:half] + "..." + p[-half:] for p in places]
    head = (f"It ran out of time ({SCAN_TIMEOUT // 60} minutes, shared between the places it looks) or could not "
            "read, in these places. They were not fully checked today")
    whole = "\n".join([head + "; everything else was.", *places, "See: journalctl -u credbroker-leakcheck"])
    if len(places) <= MAX_PLACES and len(whole) <= ALERT_LEN:
        return whole
    more = "and {} more, see the log: journalctl -u credbroker-leakcheck"
    lines = [head + "."]
    for p in places[:MAX_PLACES]:
        if len("\n".join([*lines, p, more.format(len(places))])) > ALERT_LEN:
            break
        lines.append(p)
    return "\n".join([*lines, more.format(len(places) - (len(lines) - 1))])


async def run(canary: bool = False) -> int:
    """`canary`: also plant a random fake secret in `leakcheck.canary_file`, to prove the
    whole path (scan, log line, and MQTT event when configured) works without touching a real one."""
    from .secretstore import load_secrets

    cfg = config.load()
    canary_file = cfg.leakcheck.canary_file
    if canary and not canary_file:
        raise SystemExit("credbroker-leakcheck: --canary needs leakcheck.canary_file in the config file")
    env = load_secrets()
    unread: list[tuple[str, str]] = []
    secrets, short = await load(cfg.agents, env, unread)
    if canary:
        fake = Secret("canary", "TEST canary (not a real login)", "password", "canary-" + os.urandom(12).hex())
        planted = _plant(canary_file, json.dumps({"content": f"planted for the leak check test: {fake.value}"}) + "\n")
        secrets.append(fake)
    roots = [Path(p) for root in cfg.leakcheck.roots for p in sorted(glob.glob(root))]
    hits: list[Hit] = []
    unfinished: list[str] = []
    more: Counter[Secret] = Counter()
    told: list[str] = []   # the titles of the alerts sent so far
    in_journal: list[Secret] = []
    try:
        try:
            files = (await scan_each(roots, secrets, hits, unfinished, more))[1]
        finally:
            if canary:
                _unplant(*planted)
        return _report(cfg, env, secrets, short, roots, unread, hits, more, files, unfinished, in_journal, told)
    except Exception as e:  # noqa: BLE001 - it had started on the files: whatever stopped it, the owner hears what is known
        log.exception("leak check: stopped part of the way through")
        if (hits or more or in_journal) and LEAK_TITLE not in told:
            _alert(LEAK_TITLE, FOUND_NOT_LISTED)
        _alert("The daily leak check did not finish",
               f"It stopped with an error ({type(e).__name__}) part of the way through, so today's check is not "
               "complete. What it found until then is in the log: journalctl -u credbroker-leakcheck")
        return EXIT_FAILED


def _report(cfg, env, secrets, short, roots, unread, hits, more, files, unfinished, in_journal, told) -> int:
    """Everything after the files were read: the journal, the log, the alerts and the event.
    `in_journal` and `told` are the caller's, so it knows what was found and sent if this raises."""
    first: list[str] = []   # not finished, and not a root: named ahead of the roots, which an agent can add to
    for agent, n in sorted(Counter(agent for agent, _ in unread).items()):
        first.append(f"{n} login(s) of {agent} could not be read from 1Password")
    if not roots:   # each pattern may match nothing (an agent with no ~/.claude yet), but not all of them
        first.append("leakcheck.roots in the config file: it matches no folder, so no files were searched")
    for agent, title in unread:
        log.error("leak check: %s", _line(f"{agent}/{title}: could not be read from 1Password, so not looked for"))
    try:
        scan_chunks(journal(), secrets, in_journal)
        searched = "and the broker journal"
    except Exception as e:  # noqa: BLE001 - MemoryError too: no failure here may cost what the files showed
        log.warning("could not read the broker journal to its end: %s", type(e).__name__)
        first.insert(0, "the journal of credbroker.service")
        searched = "(the broker journal was not read to its end)"
    found = [Hit(s, "journal of credbroker.service") for s in in_journal]
    _log_places(found)
    hits = hits + found
    log.info("leak check: %d secrets (%d too short to check) across %d files %s: %d match(es)",
             len(secrets), short, files, searched, len(hits) + sum(more.values()))
    if hits:
        count, places, body = _summary(hits, more)
        _alert(LEAK_TITLE, body)   # first: the event is an extra, the phone is the point
        told.append(LEAK_TITLE)
        if cfg.mqtt.url:
            try:
                events.publish_once(cfg.mqtt, env, {"ts": events.now(), "kind": "leak", "count": count, "places": places})
            except Exception as e:  # noqa: BLE001 - whatever the MQTT client raises, the leak stays a leak
                log.warning("could not publish the leak event: %s", type(e).__name__)
    unfinished = [_line(u) for u in first + unfinished]
    if unfinished:
        for u in unfinished:
            log.error("leak check: not finished: %s", u)
        _alert("The daily leak check did not finish", _unfinished(unfinished))
        return EXIT_FAILED
    return EXIT_LEAK if hits else 0


def main() -> None:
    logging.basicConfig(stream=sys.stderr, level=logging.INFO, format="%(levelname)s %(message)s")
    try:
        code = asyncio.run(run(canary="--canary" in sys.argv[1:]))
    except Exception as e:  # noqa: BLE001 - whatever stopped it, the owner must hear that it did not run
        timed_out = isinstance(e, TimeoutError)
        log.exception("leak check did not finish")
        _alert("The daily leak check did not finish",
               "It " + (f"was still reading files after {SCAN_TIMEOUT // 60} minutes" if timed_out
                        else f"stopped with an error ({type(e).__name__})")
               + ", so nothing was checked today. See: journalctl -u credbroker-leakcheck")
        sys.stdout.flush()
        sys.stderr.flush()
        os._exit(EXIT_FAILED)  # not sys.exit: a read that never returns would keep the process alive
    sys.exit(code)
