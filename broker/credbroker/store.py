"""SQLite: the request log and standing approvals. Never holds a username or password."""
from __future__ import annotations

import secrets
import sqlite3
from datetime import UTC, datetime
from pathlib import Path

# Append only: each entry runs once, in order, tracked by PRAGMA user_version.
MIGRATIONS = [
    """
    CREATE TABLE requests (
      request_id TEXT PRIMARY KEY,
      ts TEXT NOT NULL,
      agent TEXT NOT NULL,
      login_id TEXT,
      login_title TEXT,
      site TEXT NOT NULL,
      reason TEXT NOT NULL,
      decision TEXT CHECK (decision IN ('once', 'always', 'standing', 'deny', 'timeout')),
      notify_ms INTEGER,
      decide_ms INTEGER,
      fill_ms INTEGER,
      result TEXT
    );
    CREATE INDEX requests_agent_ts ON requests (agent, ts);
    CREATE TABLE standing_approvals (
      id INTEGER PRIMARY KEY,
      agent TEXT NOT NULL,
      login_id TEXT NOT NULL,
      login_title TEXT NOT NULL,
      granted_at TEXT NOT NULL,
      revoked_at TEXT,
      revoked_by TEXT
    );
    CREATE UNIQUE INDEX standing_active ON standing_approvals (agent, login_id) WHERE revoked_at IS NULL;
    """,
]

OUTCOME_FIELDS = {"login_id", "login_title", "decision", "notify_ms", "decide_ms", "fill_ms", "result"}


def now() -> str:
    return datetime.now(UTC).isoformat(timespec="seconds")


class Store:
    def __init__(self, path: Path | str):
        self._db = sqlite3.connect(str(path), isolation_level=None)
        self._db.row_factory = sqlite3.Row
        self._migrate()

    def _migrate(self) -> None:
        version = self._db.execute("PRAGMA user_version").fetchone()[0]
        for i, sql in enumerate(MIGRATIONS[version:], start=version + 1):
            self._db.executescript(f"BEGIN; {sql}; PRAGMA user_version = {i}; COMMIT;")

    def _q(self, sql: str, args: tuple = ()) -> list[sqlite3.Row]:
        return self._db.execute(sql, args).fetchall()

    # requests

    def start_request(self, agent: str, site: str, reason: str) -> str:
        request_id = secrets.token_hex(8)
        self._q("INSERT INTO requests (request_id, ts, agent, site, reason) VALUES (?, ?, ?, ?, ?)",
                (request_id, now(), agent, site, reason))
        return request_id

    def update_request(self, request_id: str, **fields) -> None:
        if bad := set(fields) - OUTCOME_FIELDS:
            raise ValueError(f"not request outcome fields: {sorted(bad)}")
        cols = ", ".join(f"{k} = ?" for k in fields)
        self._q(f"UPDATE requests SET {cols} WHERE request_id = ?", (*fields.values(), request_id))  # noqa: S608 - column names checked against OUTCOME_FIELDS

    def get_request(self, request_id: str) -> dict | None:
        rows = self._q("SELECT * FROM requests WHERE request_id = ?", (request_id,))
        return dict(rows[0]) if rows else None

    # standing approvals

    def grant(self, agent: str, login_id: str, login_title: str) -> bool:
        """False if one is already active."""
        try:
            self._q("INSERT INTO standing_approvals (agent, login_id, login_title, granted_at)"
                    " VALUES (?, ?, ?, ?)", (agent, login_id, login_title, now()))
            return True
        except sqlite3.IntegrityError:
            return False

    def is_standing(self, agent: str, login_id: str) -> bool:
        return bool(self._q("SELECT 1 FROM standing_approvals WHERE agent = ? AND login_id = ?"
                            " AND revoked_at IS NULL", (agent, login_id)))

    def approvals(self, agent: str | None = None) -> list[dict]:
        sql = "SELECT agent, login_id, login_title, granted_at FROM standing_approvals WHERE revoked_at IS NULL"
        rows = self._q(sql + " AND agent = ? ORDER BY id", (agent,)) if agent else self._q(sql + " ORDER BY id")
        return [dict(r) for r in rows]

    def revoke_missing(self, agent: str, present: set[str], by: str = "vault") -> list[str]:
        """Revoke this agent's standing approvals whose login is no longer in its vault."""
        gone = [r for r in self._q(
            "SELECT id, login_title, login_id FROM standing_approvals WHERE agent = ? AND revoked_at IS NULL", (agent,))
            if r["login_id"] not in present]
        for r in gone:
            self._q("UPDATE standing_approvals SET revoked_at = ?, revoked_by = ? WHERE id = ?", (now(), by, r["id"]))
        return [r["login_title"] for r in gone]

    def revoke(self, agent: str, login_id: str, by: str) -> bool:
        cur = self._db.execute("UPDATE standing_approvals SET revoked_at = ?, revoked_by = ?"
                               " WHERE agent = ? AND login_id = ? AND revoked_at IS NULL",
                               (now(), by, agent, login_id))
        return cur.rowcount > 0
