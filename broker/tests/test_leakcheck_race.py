"""The leak check must not be led out of a root by a link put there while it is looking.

A check for a symbolic link followed by an open of the same path is two steps, and the agent
that owns the directory can change it in between.
"""
import os

from credbroker import leakcheck
from credbroker.leakcheck import Secret, scan

PW = Secret("research", "Example", "password", "long-enough-pw")


def test_a_directory_swapped_for_a_link_mid_scan_is_not_followed(tmp_path, monkeypatch):
    """`sub` is a real directory when it is listed, and a link to someone else's by the time
    the file in it is opened."""
    outside = tmp_path / "outside"
    outside.mkdir()
    (outside / "notes.txt").write_text(f"root's own: {PW.value}")
    root = tmp_path / "home" / ".claude"
    (root / "sub").mkdir(parents=True)
    (root / "sub" / "notes.txt").write_text("nothing here")
    swapped = []
    real = os.open

    def swap_then_open(path, *a, **kw):
        if os.path.basename(os.fspath(path)) == "notes.txt" and not swapped:
            swapped.append(True)
            os.rename(root / "sub", root / "was-sub")
            os.symlink(outside, root / "sub")
        return real(path, *a, **kw)
    monkeypatch.setattr(leakcheck.os, "open", swap_then_open)
    hits, _ = scan([root], [PW])
    assert swapped, "the test did not reach the file"
    assert hits == [], f"the scan read {[h.where for h in hits]} through a link that leaves the root"


def test_a_link_higher_up_the_root_path_is_not_followed(tmp_path):
    """The root is `<home>/notes/.claude`, and the agent owns `<home>`: it can make `notes` a link."""
    outside = tmp_path / "outside"
    (outside / ".claude").mkdir(parents=True)
    (outside / ".claude" / "shadow").write_text(PW.value)
    home = tmp_path / "home"
    home.mkdir()
    if os.geteuid() == 0:
        os.chown(home, 65534, 65534)   # an agent's home; in one root owns, a link is root's own choice
    (home / "notes").symlink_to(outside)
    hits, files = scan([home / "notes" / ".claude"], [PW])
    assert (hits, files) == ([], 0)


def test_a_filesystem_mounted_inside_a_root_is_not_entered(tmp_path, monkeypatch):
    """A mount in an agent's home can be one the agent serves itself (FUSE), where a read can do anything."""
    (tmp_path / "mnt").mkdir()
    (tmp_path / "mnt" / "f").write_text(PW.value)
    (tmp_path / "here").write_text(PW.value)
    real = os.fstat

    def fstat(fd):
        st = real(fd)
        if os.readlink(f"/proc/self/fd/{fd}") == str(tmp_path / "mnt"):
            st = os.stat_result((*st[:2], st.st_dev + 1, *st[3:]))
        return st
    monkeypatch.setattr(leakcheck.os, "fstat", fstat)
    hits, files = scan([tmp_path], [PW])
    assert [h.where for h in hits] == [str(tmp_path / "here")] and files == 1


def test_hits_are_still_reported_by_their_full_path(tmp_path):
    (tmp_path / "a" / "b").mkdir(parents=True)
    (tmp_path / "a" / "b" / "t.jsonl").write_text(PW.value)
    (tmp_path / "top.txt").write_text(PW.value)
    hits, files = scan([tmp_path], [PW])
    assert sorted(h.where for h in hits) == [str(tmp_path / "a" / "b" / "t.jsonl"), str(tmp_path / "top.txt")]
    assert files == 2
