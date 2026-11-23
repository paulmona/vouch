"""Going back to a release from before the failure unit existed must not leave the broker stopped."""
import shutil
import subprocess
from pathlib import Path

BROKER = Path(__file__).parents[1]
INSTALL = BROKER / "deploy" / "install.sh"
FAILED = "credbroker-leakcheck-failed.service"

# The installer's own functions, run against folders of the test's. Only what touches
# the machine is replaced: systemctl is recorded, owners are not set, and the links
# it puts in /usr/local/bin go to a folder here.
HARNESS = r'''
source "$INSTALL"
ROOT=$T/opt ETC=$T/etc SYSTEMD=$T/systemd
systemctl() { echo "$*" >> "$T/systemctl.log"; }
getent() { return 0; }
healthy() { return 0; }
install() {
  local a=()
  while [ $# -gt 0 ]; do
    case $1 in -o|-g) shift 2 ;; *) a+=("$1"); shift ;; esac
  done
  command install "${a[@]}"
}
ln() { command ln "${@:1:$#-1}" "$T/bin/$(basename "${!#}")"; }
link() { command ln -sfn "$2" "$ROOT/.$1.new" && mv -T "$ROOT/.$1.new" "$ROOT/$1"; }
'''


def machine(tmp_path) -> None:
    """Two releases unpacked side by side: 0.1.7 has no failure unit, 0.1.8 is this tree's."""
    for d in ("opt", "etc", "systemd", "bin"):
        (tmp_path / d).mkdir()
    for v in ("0.1.7", "0.1.8"):
        shutil.copytree(BROKER / "deploy", tmp_path / "opt" / v / "deploy")
        for f in ("config.example.toml", "secrets.env.example"):
            shutil.copy(BROKER / f, tmp_path / "opt" / v / f)
    old = tmp_path / "opt" / "0.1.7" / "deploy"
    (old / FAILED).unlink()
    unit = old / "credbroker-leakcheck.service"
    unit.write_text("".join(line for line in unit.read_text().splitlines(True) if not line.startswith("OnFailure=")))


def run(tmp_path, steps: str) -> subprocess.CompletedProcess:
    return subprocess.run(["bash", "-c", HARNESS + steps], capture_output=True, text=True, timeout=60,
                          env={"PATH": "/usr/bin:/bin", "INSTALL": str(INSTALL), "T": str(tmp_path)})


def on(current: str, previous: str) -> str:
    return f'link current {current}; link previous {previous}; install_files {current}; : > "$T/systemctl.log"; '


def test_a_rollback_to_a_release_without_the_failure_unit_starts_the_broker_again(tmp_path):
    machine(tmp_path)
    r = run(tmp_path, on("0.1.8", "0.1.7") + "rollback")
    calls = (tmp_path / "systemctl.log").read_text().splitlines()
    assert r.returncode == 0, f"the broker was stopped and not started again: {r.stderr}"
    assert "credbroker is back on 0.1.7 (was 0.1.8)" in r.stdout
    assert calls.index("stop credbroker") < calls.index("daemon-reload") < calls.index("restart credbroker")
    # the older leak-check unit names no failure unit, so the newer one's is taken away with it
    assert not (tmp_path / "systemd" / FAILED).exists()
    assert "OnFailure=" not in (tmp_path / "systemd" / "credbroker-leakcheck.service").read_text()


def test_going_forward_again_puts_the_failure_unit_back(tmp_path):
    machine(tmp_path)
    r = run(tmp_path, on("0.1.7", "0.1.8") + "rollback")
    assert r.returncode == 0, r.stderr
    assert (tmp_path / "systemd" / FAILED).read_text() == (BROKER / "deploy" / FAILED).read_text()
    assert "OnFailure=credbroker-leakcheck-failed.service" in (tmp_path / "systemd" / "credbroker-leakcheck.service").read_text()
