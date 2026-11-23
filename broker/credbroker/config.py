"""Settings: the config file (agents, leak check, MQTT) and fixed paths."""
from __future__ import annotations

import logging
import os
import pwd
import tomllib
from dataclasses import dataclass, field
from pathlib import Path

log = logging.getLogger("credbroker")

SOCKET_PATH = os.environ.get("CREDBROKER_SOCKET", "/run/credbroker/broker.sock")
SOCKET_GROUP = "credbroker-clients"
DB_PATH = os.environ.get("CREDBROKER_DB", "/var/lib/credbroker/broker.db")
CONFIG_FILE = Path(os.environ.get("CREDBROKER_CONFIG", "/etc/credbroker/config.toml"))
VOUCH_SOCKET = os.environ.get("CREDBROKER_VOUCH_SOCKET", "/run/vouch/broker.sock")
# What the port guard says it is enforcing: "port uid" per line. Empty turns the check off,
# for a machine that restricts the DevTools ports some other way.
GUARD_STATE = os.environ.get("CREDBROKER_GUARD_STATE", "/run/vouch-browser/guarded")

FIELDS = {"op_token_key": str, "cdp_port": int, "admin": bool}
LEAKCHECK_FIELDS = {"roots": list, "canary_file": str}
MQTT_FIELDS = {"url": str, "event_topic": str, "status_topic": str, "ha_discovery": bool}


@dataclass(frozen=True)
class Agent:
    name: str
    uid: int
    admin: bool = False
    op_token_key: str | None = None
    cdp_port: int | None = None


@dataclass(frozen=True)
class Leakcheck:
    """Where the daily leak check looks. `roots` are paths or globs."""
    roots: tuple[str, ...] = ("/home/*/.claude", "/var/lib/credbroker")
    canary_file: str | None = None


@dataclass(frozen=True)
class Mqtt:
    """Where events and the heartbeat are published. Off unless `url` is set."""
    url: str | None = None
    event_topic: str = "credbroker/events"
    status_topic: str = "credbroker/status"
    ha_discovery: bool = False


@dataclass(frozen=True)
class Config:
    agents: dict[int, Agent]  # keyed by uid
    leakcheck: Leakcheck = field(default_factory=Leakcheck)
    mqtt: Mqtt = field(default_factory=Mqtt)


def _checked(path: Path, where: str, given: dict, fields: dict[str, type]) -> dict:
    """Refuse a field that is not known or not of its kind. `admin = "false"` must not read as yes."""
    if not isinstance(given, dict):
        raise ValueError(f"{path}: {where} must be a table")
    if extra := set(given) - set(fields):
        raise ValueError(f"{path}: {where}: unknown field(s) {sorted(extra)}")
    for key, value in given.items():
        kind = fields[key]
        # In Python true is also the number 1: a port must be a number and nothing else.
        if type(value) is not kind:
            raise ValueError(f"{path}: {where}.{key} must be {NAMES[kind]}, without quotes"
                             if kind in (bool, int) else f"{path}: {where}.{key} must be {NAMES[kind]}")
    return given


NAMES = {bool: "true or false", int: "a whole number", str: "text in quotes", list: "a list"}


def load(path: Path = CONFIG_FILE) -> Config:
    """Read the config file. A listed user that does not exist on this host is skipped."""
    try:
        with open(path, "rb") as f:
            table = tomllib.load(f)
    except FileNotFoundError:
        raise SystemExit(f"credbroker: no config file at {path} (set CREDBROKER_CONFIG to use another path)") from None
    if extra := set(table) - {"agents", "leakcheck", "mqtt"}:
        raise ValueError(f"{path}: unknown table(s) {sorted(extra)}")
    agents: dict[int, Agent] = {}
    for name, a in table.get("agents", {}).items():
        _checked(path, f"agents.{name}", a, FIELDS)
        try:
            uid = pwd.getpwnam(name).pw_uid
        except KeyError:
            log.warning("agents.%s: no such user on this host, skipped", name)
            continue
        agents[uid] = Agent(name=name, uid=uid, **a)
    lc = _checked(path, "leakcheck", table.get("leakcheck", {}), LEAKCHECK_FIELDS)
    if "roots" in lc:
        if not all(type(r) is str for r in lc["roots"]):
            raise ValueError(f"{path}: leakcheck.roots must be a list of text in quotes")
        lc = {**lc, "roots": tuple(lc["roots"])}
    mq = _checked(path, "mqtt", table.get("mqtt", {}), MQTT_FIELDS)
    if "url" in mq and not mq["url"].startswith(("mqtt://", "mqtts://")):
        raise ValueError(f"{path}: mqtt.url must start with mqtts:// (TLS) or mqtt://")
    return Config(agents, Leakcheck(**lc), Mqtt(**mq))
