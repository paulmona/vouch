import asyncio
import json
import socketserver
import threading
from datetime import UTC, datetime
from http.server import BaseHTTPRequestHandler

import pytest
from test_signin import PAGE, RESEARCH, SECRET, Bus, Vault, env, no_secrets, sign_in  # noqa: F401 - env is a fixture

from credbroker.approval import ApprovalError, Prompt, VouchApprovals
from credbroker.server import Broker
from credbroker.store import Store

P = Prompt("ab12cd34ef56ab12", "research", "portal.example.com", "alex@example.com", "check balance", "Example")


class FakeVouch(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
    """Vouch's broker socket: answers `final` after `polls` pending long polls."""
    daemon_threads = True

    def __init__(self, path, final="once", polls=2, create_status=202):
        self.final, self.polls, self.create_status = final, polls, create_status
        self.created, self.waits, self.cancelled, self.alerts = [], [], [], []
        super().__init__(str(path), Handler)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, status, body=None):
        raw = json.dumps(body).encode() if body is not None else b""
        self.send_response(status)
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_POST(self):
        s = self.server
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length") or 0)) or b"null")
        if self.path == "/v1/approvals":
            s.created.append(body)
            return self._send(s.create_status, {"request_id": body["request_id"], "state": "pending"})
        if self.path == "/v1/alerts":
            s.alerts.append(body)
            return self._send(getattr(s, "alert_status", 202), {"alert_id": body["alert_id"]})
        s.cancelled.append(self.path.split("/")[3])
        self._send(204)

    def do_GET(self):
        s = self.server
        s.waits.append(self.path)
        state = "pending" if len(s.waits) <= s.polls else s.final
        self._send(200, {"request_id": self.path.split("/")[3].split("?")[0], "state": state})


@pytest.fixture
def vouch(tmp_path):
    started = []

    def start(**kw):
        srv = FakeVouch(tmp_path / "broker.sock", **kw)
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        started.append(srv)
        return srv, VouchApprovals(str(tmp_path / "broker.sock"))
    yield start
    for s in started:
        s.shutdown()
        s.server_close()


@pytest.mark.parametrize("final", ["once", "always", "deny", "timeout"])
def test_decisions_pass_through_after_long_polls(vouch, final):
    srv, a = vouch(final=final)
    d = asyncio.run(a.ask(P))
    assert d.decision == final and d.notify_ms >= 0 and d.decide_ms >= 0
    assert srv.waits == ["/v1/approvals/ab12cd34ef56ab12?wait=30"] * 3


def test_request_carries_no_username_or_reason(vouch):
    srv, a = vouch()
    asyncio.run(a.ask(P))
    (c,) = srv.created
    assert set(c) == {"request_id", "kind", "agent", "site", "login_title", "expires_at"}
    assert (c["kind"], c["agent"], c["site"], c["login_title"]) == ("sign_in", "Research", P.site, "Example")
    left = datetime.fromisoformat(c["expires_at"]) - datetime.now(UTC)
    assert 290 < left.total_seconds() <= 300
    assert P.username not in json.dumps(c) and P.reason not in json.dumps(c)


def test_cancelled_elsewhere_is_never_a_yes(vouch):
    _, a = vouch(final="cancelled")
    assert asyncio.run(a.ask(P)).decision == "timeout"


def test_refused_create_and_missing_socket_raise_approval_error(vouch, tmp_path):
    _, a = vouch(create_status=409)
    with pytest.raises(ApprovalError, match="HTTP 409"):
        asyncio.run(a.ask(P))
    with pytest.raises(ApprovalError, match="FileNotFoundError"):
        asyncio.run(VouchApprovals(str(tmp_path / "nothing.sock")).ask(P))


def test_broker_giving_up_cancels_on_vouch(vouch):
    srv, a = vouch(polls=10_000)

    async def go():
        task = asyncio.create_task(a.ask(P))
        while not srv.waits:
            await asyncio.sleep(0.01)
        task.cancel()
        with pytest.raises(asyncio.CancelledError):
            await task
    asyncio.run(go())
    assert srv.cancelled == [P.request_id]


def test_sign_in_end_to_end_through_vouch(env, vouch, tmp_path):
    _, tabs = env
    srv, a = vouch(final="once")
    bus = Bus()
    b = Broker({1003: RESEARCH}, {"research": Vault()}, Store(tmp_path / "e.db"), a, bus)
    r = sign_in(b)
    assert r["ok"] and r["result"] == "signed_in" and "Sign out of portal.example.com" in r["sign_out"]
    assert tabs["filled"] == [True]
    (e,) = bus.events
    assert e["decision"] == "once" and e["result"] == "signed_in"
    assert srv.created[0]["request_id"] == e["request_id"]
    assert no_secrets(r, bus.events, srv.created)


def test_always_through_vouch_becomes_a_standing_approval(env, vouch, tmp_path):
    srv, a = vouch(final="always", polls=0)
    b = Broker({1003: RESEARCH}, {"research": Vault()}, Store(tmp_path / "s.db"), a, Bus())
    assert sign_in(b)["result"] == "signed_in"
    assert sign_in(b)["result"] == "signed_in"
    assert len(srv.created) == 1, "the second sign-in uses the standing approval, not Vouch"



def test_text_an_agent_chose_cannot_get_an_alert_refused(vouch):
    """Vouch refuses control and invisible characters. A leaked file's name is the agent's to choose."""
    srv, a = vouch()
    a.alert("leak_0123456789", "critical", "A password\x07 is where an agent can read it",
            "Found here.\nresearch/Example (password) in /home/research/a\u202eb\u200b\x00c\u2028d.txt")
    (sent,) = srv.alerts
    assert sent["title"] == "A password? is where an agent can read it"
    assert sent["body"] == "Found here.\nresearch/Example (password) in /home/research/a?b??c?d.txt"


def test_an_unassigned_character_cannot_get_an_alert_refused(vouch):
    """Vouch also refuses code points Unicode has not assigned: they may be drawn as nothing."""
    srv, a = vouch()
    a.alert("leak_0123456789", "critical", "A password is where an agent can read it",
            "research/Example (password) in /home/research/a\u0378b.txt")
    (sent,) = srv.alerts
    assert sent["body"] == "research/Example (password) in /home/research/a?b.txt"


def test_a_login_title_is_sent_without_hidden_characters(vouch):
    srv, a = vouch(polls=0)
    asyncio.run(a.ask(Prompt("ab12cd34ef56ab12", "research", "portal.example.com", "alex@example.com", "", "Exa\u202emple\tbank")))
    assert srv.created[0]["login_title"] == "Exa?mple?bank"


def test_a_symbol_drawn_as_nothing_cannot_get_an_alert_or_a_request_refused(vouch):
    """Vouch refuses the null notehead and the object replacement character: they show nothing."""
    srv, a = vouch(polls=0)
    a.alert("leak_0123456789", "critical", "A password is where an agent can read it",
            "research/Example (password) in /home/research/a\U0001d159b￼c.txt")
    assert srv.alerts[0]["body"] == "research/Example (password) in /home/research/a?b?c.txt"
    asyncio.run(a.ask(Prompt("ab12cd34ef56ab12", "research", "portal.example.com", "alex@example.com", "", "￼")))
    assert srv.created[0]["login_title"] == "?"
