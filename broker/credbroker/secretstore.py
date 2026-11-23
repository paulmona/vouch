"""The broker's secrets: each agent's 1Password token and the logins for the services it talks to.

By default they come from a file only root and the broker can read. With
VAULT_ADDR set they come from HashiCorp Vault instead (see vault.py). Agents can
read neither, so they cannot call 1Password themselves and skip approval.
"""
from __future__ import annotations

import os
from pathlib import Path

SECRETS_FILE = "/etc/credbroker/secrets.env"


def parse_env(text: str) -> dict[str, str]:
    """KEY=value lines. Blank lines and # comments are skipped; one pair of quotes around a value is dropped."""
    out: dict[str, str] = {}
    for n, line in enumerate(text.splitlines(), 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        key, sep, value = line.partition("=")
        key, value = key.strip(), value.strip()
        if not sep or not key.replace("_", "").isalnum():
            raise ValueError(f"line {n}: expected KEY=value")
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        out[key] = value
    return out


def load_secrets(env=os.environ) -> dict[str, str]:
    if env.get("VAULT_ADDR"):
        from .vault import read
        return read(env["VAULT_ADDR"], env.get("CREDBROKER_VAULT_PATH", ""),
                    Path(env.get("CREDBROKER_VAULT_CREDS", Path.home() / ".vault-creds")))
    path = Path(env.get("CREDBROKER_SECRETS", SECRETS_FILE))
    try:
        text = path.read_text()
    except FileNotFoundError:
        raise SystemExit(f"credbroker: no secrets file at {path} (set CREDBROKER_SECRETS to use another path, "
                         "or VAULT_ADDR to read from Vault)") from None
    try:
        return parse_env(text)
    except ValueError as e:
        raise SystemExit(f"credbroker: {path}: {e}") from None
