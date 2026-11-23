"""Talk to the broker from an agent's own unix user."""
from __future__ import annotations

import json
import socket
import sys

from .config import SOCKET_PATH

# sign_in waits up to 5 minutes for the owner's tap.
TIMEOUT = 330


def call(op: str, path: str = SOCKET_PATH, **args) -> dict:
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.settimeout(TIMEOUT)
        s.connect(path)
        s.sendall(json.dumps({"op": op, **args}).encode() + b"\n")
        line = s.makefile("rb").readline()
    return json.loads(line)


USAGE = """usage: credbroker whoami
       credbroker logins
       credbroker approvals [--all]
       credbroker revoke --mine <login title>
       credbroker revoke <agent> <login title>     (admins)"""


def parse(argv: list[str]) -> tuple[str, dict]:
    match argv:
        case ["whoami"] | ["logins"]:
            return argv[0], {}
        case ["approvals"]:
            return "approvals", {}
        case ["approvals", "--all"]:
            return "approvals", {"all": True}
        case ["revoke", "--mine", *title] if title:
            return "revoke", {"login": " ".join(title)}
        case ["revoke", agent, *title] if title:
            return "revoke", {"agent": agent, "login": " ".join(title)}
    sys.exit(USAGE)


def main() -> None:
    op, args = parse(sys.argv[1:])
    try:
        resp = call(op, **args)
    except (FileNotFoundError, ConnectionRefusedError):
        sys.exit(f"credbroker: broker not running ({SOCKET_PATH})")
    except PermissionError:
        sys.exit(f"credbroker: no access to {SOCKET_PATH} (not in group credbroker-clients?)")
    print(json.dumps(resp))
    sys.exit(0 if resp.get("ok") else 1)
