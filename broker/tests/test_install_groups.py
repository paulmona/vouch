"""The broker installer warns when an agent's own user can reach Vouch's socket directly."""
import grp
import os
import pwd
import subprocess
from pathlib import Path

INSTALL = Path(__file__).parents[1] / "deploy" / "install.sh"
ME = pwd.getpwuid(os.getuid()).pw_name
MY_GROUP = grp.getgrgid(os.getgid()).gr_name


def next_steps(tmp_path, config: str, vouch_group: str) -> str:
    (tmp_path / "config.toml").write_text(config)
    (tmp_path / "secrets.env").write_text("OP_TOKEN_A=ops_x\n")
    script = f'source "{INSTALL}"; ETC="{tmp_path}"; VOUCH_GROUP="{vouch_group}"; PYTHON=python3; next_steps'
    r = subprocess.run(["bash", "-c", script], capture_output=True, text=True, timeout=30)
    assert r.returncode == 0, r.stderr
    return r.stdout


def test_an_agent_in_vouchs_group_is_called_out(tmp_path):
    out = next_steps(tmp_path, f'[agents.{ME}]\nop_token_key = "OP_TOKEN_A"\ncdp_port = 9222\n', MY_GROUP)
    assert f"warning: {ME} is an agent and is in {MY_GROUP}" in out
    assert f"sudo gpasswd -d {ME} {MY_GROUP}" in out


def test_no_warning_for_an_agent_outside_it_or_for_the_owners_own_entry(tmp_path):
    # `root` exists everywhere and is not in this user's group; an entry with no token is the owner, not an agent
    config = f'[agents.root]\nop_token_key = "OP_TOKEN_A"\ncdp_port = 9222\n[agents.{ME}]\nadmin = true\n'
    assert "warning" not in next_steps(tmp_path, config, MY_GROUP)
