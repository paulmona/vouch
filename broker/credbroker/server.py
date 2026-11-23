"""The broker service: a unix socket that knows which agent is calling.

One JSON request line in, one JSON response line out, then the connection closes.
The caller is whoever the kernel says is on the other end (SO_PEERCRED), never
anything the request claims.
"""
from __future__ import annotations

import asyncio
import grp
import json
import logging
import os
import re
import socket
import struct
import sys
import traceback

from . import cdp, config
from .approval import ApprovalError, Decision, Prompt, VouchApprovals
from .assisted import ASSIST_TTL, Assisted, FieldRefused, type_into
from .config import Agent
from .events import Bus
from .fill import FillFailed, _find, answer_for, fill
from .match import NoMatch, choose, parse, site_matches
from .onepw import AgentVault, Login, OnePasswordError
from .store import Store

log = logging.getLogger("credbroker")

MAX_REQUEST = 64 * 1024
MAX_REASON = 200
# Longer than any real page address. The address is stored, logged and published as sent.
MAX_URL = 2048
URL_TOO_LONG = {"ok": False, "error": "url_too_long",
                "message": f"the page url is longer than {MAX_URL} characters"}
READ_TIMEOUT = 10
_PEERCRED = struct.Struct("3i")   # pid, uid, gid


def matcher(login: Login):
    """The website check for this login, applied to a live tab URL."""
    return lambda url: any(site_matches(parse(url), w) for w in login.websites)


async def fillable(tab) -> str | None:
    """Why the automatic fill cannot work on this page, before the owner is asked; None if it can try."""
    async with cdp.Session(tab) as s:
        if not (await _find(s)).get("pass"):
            return "no password field on the page; for a multi-step login use begin_sign_in"
    return None


def peer(writer: asyncio.StreamWriter) -> tuple[int, int]:
    sock = writer.get_extra_info("socket")
    pid, uid, _ = _PEERCRED.unpack(sock.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, _PEERCRED.size))
    return pid, uid


# Told to the agent after a sign-in approved for once. The broker cannot make it sign
# out: the browser is the agent's.
SIGN_OUT = ("Your owner approved this sign-in once, not for every time. Sign out of %s when the"
            " task you needed it for is done, and do not use the session for anything else.")


class Broker:
    def __init__(self, agents: dict[int, Agent], vaults: dict[str, AgentVault], store: Store,
                 approvals: VouchApprovals | None = None, bus: Bus | None = None):
        self.agents = agents
        self.vaults = vaults
        self.store = store
        self.approvals = approvals
        self.bus = bus
        self.ops = {"whoami": self.whoami, "logins": self.logins, "sign_in": self.sign_in,
                    "begin_sign_in": self.begin_sign_in, "fill_field": self.fill_field,
                    "end_sign_in": self.end_sign_in,
                    "approvals": self.list_approvals, "revoke": self.revoke}
        self.assisted = Assisted()
        self._busy: dict[str, asyncio.Lock] = {}

    async def sign_in(self, agent: Agent, req: dict) -> dict:
        url, reason = req.get("url"), req.get("reason")
        if not isinstance(url, str) or not isinstance(reason, str) or not reason.strip():
            return {"ok": False, "error": "bad_request", "message": "sign_in needs the page url and a reason"}
        if len(url) > MAX_URL:
            return dict(URL_TOO_LONG)
        reason = " ".join(reason.split())[:MAX_REASON]
        rid = self.store.start_request(agent.name, url, reason)
        # One sign-in per agent at a time: two prompts racing to fill one tab helps nobody.
        try:
            async with self._busy.setdefault(agent.name, asyncio.Lock()):
                outcome = await self._sign_in(agent, url, reason, rid)
        except Exception:
            self._finish(rid, {"result": "error"})
            raise
        self._finish(rid, outcome)
        result = outcome["result"]
        resp = {"ok": result == "signed_in", "result": result}
        if outcome.get("reason"):
            resp["reason"] = outcome["reason"]
        if resp["ok"] and outcome.get("sign_out"):
            resp["sign_out"] = outcome["sign_out"]
        return resp

    async def _approve(self, agent: Agent, url: str, reason: str, rid: str,
                       precheck=None, need_password: bool = False) -> tuple[dict, tuple | None]:
        """Find the tab, match its login, and get approval. Returns the request outcome so
        far and, if approved, (tab, login, creds)."""
        vault = self.vaults.get(agent.name)
        if vault is None or agent.cdp_port is None:
            return {"result": "no_login", "reason": "this agent has no 1Password vault or browser set up"}, None
        if not cdp.guarded(agent.cdp_port, agent.uid, config.GUARD_STATE):
            log.error("%s: port %s is not restricted to this agent by the port guard (%s); nothing typed",
                      agent.name, agent.cdp_port, config.GUARD_STATE)
            return {"result": "fill_failed", "reason": "the browser's port is not protected by the port guard;"
                                                       " your owner needs to run: sudo vouch-cdp-guard load"}, None
        try:
            tab = await cdp.find_tab(agent.cdp_port, url, agent.uid)
            # Match the tab's own URL, not the one the agent sent.
            login = choose(tab.url, await self._logins(agent.name))
            if precheck and (refusal := await precheck(tab)):
                return {"login_id": login.id, "login_title": login.title, "result": "fill_failed",
                        "reason": refusal}, None
            creds = await vault.credentials(login.id)
            if need_password and not creds.password:
                return {"login_id": login.id, "login_title": login.title, "result": "fill_failed",
                        "reason": "this login has no password (a one-time code sign-in); use begin_sign_in"}, None
        except cdp.BrowserError as e:
            return {"result": "fill_failed", "reason": {"tab_not_found": "no open tab shows that page",
                                                        "browser_unavailable": "the browser is not reachable"
                                                        }.get(e.code, "browser error")}, None
        except NoMatch as e:
            return {"result": "no_login" if e.code == "no_login" else "site_mismatch",
                    "reason": {"ambiguous_login": "more than one login matches this site",
                               "no_login": f"no login in your vault for {parse(tab.url).host if parse(tab.url) else 'this page'};"
                                           " if the sign-in form is on another site, that site needs to be"
                                           " a website on the 1Password item"}.get(e.code)}, None
        except OnePasswordError as e:
            log.error("%s", e)
            return {"result": "fill_failed", "reason": "1Password is unavailable"}, None
        out = {"login_id": login.id, "login_title": login.title}
        try:
            d = await self.authorize(agent, login, parse(tab.url).host, creds.username, reason, rid)
        except NoMatch:
            return {**out, "result": "no_login"}, None
        except ApprovalError as e:
            log.error("%s: %s", agent.name, e)
            return {**out, "result": "fill_failed",
                    "reason": "your owner's phone could not be asked (the approval server refused the request"
                              " or is not running); nothing was typed"}, None
        out |= {"decision": d.decision, "notify_ms": d.notify_ms, "decide_ms": d.decide_ms}
        # Written down now, not when the fill is over: whatever happens next, the record
        # says the owner was asked and what they answered.
        self.store.update_request(rid, **out)
        if d.decision in ("deny", "timeout"):
            return {**out, "result": "denied" if d.decision == "deny" else "timeout"}, None
        if d.decision == "once":
            out["sign_out"] = SIGN_OUT % parse(tab.url).host
        return out, (tab, login, creds)

    async def _sign_in(self, agent: Agent, url: str, reason: str, rid: str) -> dict:
        out, ok = await self._approve(agent, url, reason, rid, precheck=fillable, need_password=True)
        if ok is None:
            return out
        tab, login, creds = ok
        try:
            async with cdp.Session(tab) as s:
                r = await fill(s, creds, matcher(login))
        except NoMatch:
            return {**out, "result": "site_mismatch", "reason": "the page moved to another site before filling"}
        except cdp.BrowserError as e:
            log.warning("%s: fill on %s: %s", agent.name, rid, e.code)
            return {**out, "result": "fill_failed", "reason": "the browser stopped responding"}
        return {**out, "result": r.result, "reason": r.reason, "fill_ms": r.fill_ms}

    # Assisted fill: the agent drives the page; the broker only types secrets into the
    # fields it points at, on the matching site, after approval.

    async def begin_sign_in(self, agent: Agent, req: dict) -> dict:
        url, reason = req.get("url"), req.get("reason")
        if not isinstance(url, str) or not isinstance(reason, str) or not reason.strip():
            return {"ok": False, "error": "bad_request", "message": "begin_sign_in needs the page url and a reason"}
        if len(url) > MAX_URL:
            return dict(URL_TOO_LONG)
        reason = " ".join(reason.split())[:MAX_REASON]
        rid = self.store.start_request(agent.name, url, reason)
        try:
            async with self._busy.setdefault(agent.name, asyncio.Lock()):
                out, ok = await self._approve(agent, url, reason, rid)
        except Exception:
            self._finish(rid, {"result": "error"})
            raise
        if ok is None:
            self._finish(rid, out)
            resp = {"ok": False, "result": out["result"]}
            if out.get("reason"):
                resp["reason"] = out["reason"]
            return resp
        tab, login, creds = ok
        h = self.assisted.open(agent.name, rid, tab, login, creds, out, on_expire=self._finish)
        return {"ok": True, "handle": h.id, "expires_in": ASSIST_TTL,
                "secrets": ["username"] + (["password"] if creds.password else [])
                           + (["answer"] if creds.extras else []),
                "questions": sorted(creds.extras),
                **({"sign_out": out["sign_out"]} if "sign_out" in out else {})}

    async def fill_field(self, agent: Agent, req: dict) -> dict:
        h = self.assisted.get(req.get("handle"), agent.name)
        if h is None:
            return {"ok": False, "error": "no_handle", "message": "unknown or expired handle; call begin_sign_in again"}
        selector, secret = req.get("selector"), req.get("secret")
        if not isinstance(selector, str) or secret not in ("username", "password", "answer"):
            return {"ok": False, "error": "bad_request", "message": "fill_field needs a selector and secret username, password or answer"}
        if secret == "answer":  # noqa: S105 - a secret's name, not a value
            value = answer_for(str(req.get("question") or ""), h.creds.extras)
            if value is None:
                return {"ok": False, "error": "no_answer", "message": "no single answer in 1Password matches that question"}
        else:
            value = getattr(h.creds, secret)
            if not value:
                return {"ok": False, "error": f"no_{secret}", "message": f"this login has no {secret} in 1Password"}
        try:
            async with cdp.Session(h.tab) as s:
                await type_into(s, selector, value, secret, matcher(h.login))
        except NoMatch:
            self._finish(h.request_id, {**self.assisted.close(h), "result": "site_mismatch"})
            return {"ok": False, "error": "site_mismatch", "message": "the tab is no longer on the login's site; the handle is closed"}
        except FieldRefused as e:
            return {"ok": False, "error": "field_refused", "message": str(e)}
        except (FillFailed, cdp.BrowserError) as e:
            return {"ok": False, "error": "fill_failed", "message": str(e) if isinstance(e, FillFailed) else "the browser stopped responding"}
        h.fills += 1
        return {"ok": True, "result": "typed"}

    async def end_sign_in(self, agent: Agent, req: dict) -> dict:
        h = self.assisted.get(req.get("handle"), agent.name)
        if h is None:
            return {"ok": False, "error": "no_handle"}
        signed_in = req.get("signed_in") is True
        self._finish(h.request_id, {**self.assisted.close(h),
                                    "result": "assisted_signed_in" if signed_in else "assisted_failed"})
        return {"ok": True}

    def _finish(self, rid: str, outcome: dict) -> None:
        self.store.update_request(rid, **{k: v for k, v in outcome.items() if k not in ("reason", "sign_out")})
        if self.bus:
            self.bus.emit(self.store.get_request(rid))

    async def authorize(self, agent: Agent, login: Login, site: str, username: str,
                        reason: str, request_id: str) -> Decision:
        """Standing approval, or ask the owner. Raises NoMatch("no_login") if a standing
        approval's login has left the agent's vault."""
        if self.store.is_standing(agent.name, login.id):
            fresh = await self.vaults[agent.name].logins(fresh=True)
            if all(l.id != login.id for l in fresh):
                self.store.revoke(agent.name, login.id, by="vault")
                log.info("%s: standing approval for %r revoked, login left the vault", agent.name, login.title)
                raise NoMatch("no_login")
            return Decision("standing", 0, 0)
        d = await self.approvals.ask(Prompt(request_id, agent.name, site, username, reason, login.title))
        if d.decision == "always":
            self.store.grant(agent.name, login.id, login.title)
        return d

    async def _logins(self, name: str) -> list[Login]:
        """The agent's logins, and any standing approval whose login has left its vault revoked."""
        logins = await self.vaults[name].logins()
        for title in self.store.revoke_missing(name, {l.id for l in logins}):
            log.info("%s: standing approval for %r revoked, login left the vault", name, title)
        return logins

    async def list_approvals(self, agent: Agent, req: dict) -> dict:
        everyone = agent.admin and req.get("all") is True
        for name in (self.vaults if everyone else [agent.name] if agent.name in self.vaults else []):
            try:
                await self._logins(name)
            except OnePasswordError as e:
                log.error("%s", e)
        return {"ok": True, "approvals": self.store.approvals(None if everyone else agent.name)}

    async def revoke(self, agent: Agent, req: dict) -> dict:
        # Revoking only takes access away, so an agent may always give up its own
        # standing approvals. Another agent's needs an admin.
        target, title = req.get("agent", agent.name), req.get("login")
        if not isinstance(target, str) or not isinstance(title, str):
            return {"ok": False, "error": "bad_request"}
        if target != agent.name and not agent.admin:
            return {"ok": False, "error": "not_admin"}
        hits = [a for a in self.store.approvals(target) if a["login_title"].casefold() == title.casefold()]
        if not hits:
            return {"ok": False, "error": "not_found"}
        for a in hits:
            self.store.revoke(target, a["login_id"], by=agent.name)
        log.info("%s revoked %s's standing approval for %r", agent.name, target, title)
        return {"ok": True, "revoked": len(hits)}

    async def whoami(self, agent: Agent, req: dict) -> dict:
        return {"ok": True, "agent": agent.name, "admin": agent.admin}

    async def logins(self, agent: Agent, req: dict) -> dict:
        vault = self.vaults.get(agent.name)
        if vault is None:
            return {"ok": False, "error": "no_vault"}
        try:
            logins = await self._logins(agent.name)
        except OnePasswordError as e:
            log.error("%s", e)
            return {"ok": False, "error": "vault_unavailable"}
        return {"ok": True, "logins": [{"title": l.title, "websites": [w.url for w in l.websites]}
                                       for l in logins]}

    async def handle(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        try:
            pid, uid = peer(writer)
            agent = self.agents.get(uid)
            if agent is None:
                log.warning("refused: uid %d (pid %d) is not a broker agent", uid, pid)
                resp = {"ok": False, "error": "unknown_caller"}
            else:
                try:
                    resp = await self._dispatch(agent, reader)
                except Exception as e:  # noqa: BLE001 - the caller is always answered
                    # The kind of error and where, never its message: that can repeat what a page said.
                    at = traceback.extract_tb(e.__traceback__)[-1]
                    log.error("%s: internal error: %s at %s:%d", agent.name, type(e).__name__,
                              os.path.basename(at.filename), at.lineno)
                    resp = {"ok": False, "error": "internal"}
                log.info("%s %s -> %s", agent.name, resp.pop("_op", "?"),
                         resp.get("result") or ("ok" if resp.get("ok") else resp.get("error")))
            writer.write(json.dumps(resp).encode() + b"\n")
            await writer.drain()
        except (ConnectionError, BrokenPipeError):
            pass
        finally:
            writer.close()

    async def _dispatch(self, agent: Agent, reader: asyncio.StreamReader) -> dict:
        try:
            line = await asyncio.wait_for(reader.readline(), READ_TIMEOUT)
            req = json.loads(line)
            op = req["op"]
        except (TimeoutError, ValueError, KeyError, TypeError):
            return {"ok": False, "error": "bad_request"}
        handler = self.ops.get(op) if isinstance(op, str) else None
        if handler is None:
            # The caller chose this text and it goes to the log: a plain name or nothing.
            named = isinstance(op, str) and re.fullmatch(r"[a-z_]{1,40}", op)
            return {"ok": False, "error": "unknown_op", "_op": op if named else "?"}
        return {**await handler(agent, req), "_op": op}

    async def serve(self, path: str, group: str | None = config.SOCKET_GROUP) -> asyncio.AbstractServer:
        if os.path.exists(path):
            os.unlink(path)
        server = await asyncio.start_unix_server(self.handle, path=path, limit=MAX_REQUEST)
        if group:
            os.chown(path, -1, grp.getgrnam(group).gr_gid)
        os.chmod(path, 0o660)
        return server


async def run() -> None:
    from .secretstore import load_secrets

    cfg = config.load()
    agents = cfg.agents
    secrets = load_secrets()
    vaults = {}
    for a in agents.values():
        if not a.op_token_key:
            continue
        if a.op_token_key in secrets:
            vaults[a.name] = AgentVault(a.name, secrets[a.op_token_key])
        else:
            log.warning("%s: no secret named %s; it has no logins", a.name, a.op_token_key)
    store = Store(config.DB_PATH)
    bus = Bus(cfg.mqtt, secrets) if cfg.mqtt.url else None
    if bus:
        bus.start()
    broker = Broker(agents, vaults, store, VouchApprovals(config.VOUCH_SOCKET), bus)
    log.info("approvals through Vouch at %s", config.VOUCH_SOCKET)
    server = await broker.serve(config.SOCKET_PATH)
    log.info("listening on %s for %s", config.SOCKET_PATH,
             ", ".join(sorted(a.name for a in agents.values())))
    heartbeat = asyncio.create_task(bus.heartbeat()) if bus else None
    async with server:
        await server.serve_forever()
    if heartbeat:
        heartbeat.cancel()


def main() -> None:
    logging.basicConfig(stream=sys.stderr, level=logging.INFO, format="%(levelname)s %(message)s")
    asyncio.run(run())
