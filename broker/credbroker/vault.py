"""Optional: read the broker's secrets from HashiCorp Vault once, at startup, with its AppRole."""
from __future__ import annotations

import json
import re
import urllib.error
import urllib.request
from pathlib import Path


class VaultError(Exception):
    pass


def _call(addr: str, method: str, path: str, token: str | None = None, body: dict | None = None) -> dict:
    req = urllib.request.Request(f"{addr.rstrip('/')}/v1/{path}", method=method,
                                 data=json.dumps(body).encode() if body is not None else None)
    if token:
        req.add_header("X-Vault-Token", token)
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            raw = r.read()
    except urllib.error.HTTPError as e:
        raise VaultError(f"{method} {path}: HTTP {e.code}") from None
    except OSError as e:
        raise VaultError(f"{method} {path}: {type(e).__name__}") from None
    return json.loads(raw) if raw else {}


def read(addr: str, path: str, creds: Path) -> dict[str, str]:
    """`path` is the secret's KV v2 API path, e.g. secret/data/credbroker. `creds` holds role_id and secret_id."""
    if not re.fullmatch(r"[A-Za-z0-9_-]+(/[A-Za-z0-9_.-]+)+", path):
        raise VaultError("CREDBROKER_VAULT_PATH must be the secret's KV v2 API path, like secret/data/credbroker")
    login = _call(addr, "POST", "auth/approle/login", body={
        "role_id": (creds / "role_id").read_text().strip(),
        "secret_id": (creds / "secret_id").read_text().strip(),
    })
    token = login["auth"]["client_token"]
    try:
        return _call(addr, "GET", path, token)["data"]["data"]
    finally:
        try:
            _call(addr, "POST", "auth/token/revoke-self", token)
        except VaultError:
            pass  # it expires on its own within the hour
