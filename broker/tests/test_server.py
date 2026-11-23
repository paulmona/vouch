import asyncio
import getpass
import grp
import json
import os
import socket
from pathlib import Path

import pytest

from credbroker import client, server
from credbroker.config import Agent, Config, Leakcheck, Mqtt, load
from credbroker.onepw import Login, OnePasswordError, Website
from credbroker.server import Broker
from credbroker.store import Store

ME = os.getuid()


class StubVault:
    def __init__(self, logins=None, fail=False):
        self._logins, self._fail = logins or [], fail

    async def logins(self):
        if self._fail:
            raise OnePasswordError("research: list failed: RateLimitExceeded")
        return self._logins


def serve(tmp_path, agents, vaults=None):
    path = str(tmp_path / "b.sock")
    loop = asyncio.new_event_loop()
    broker = Broker(agents, vaults or {}, Store(tmp_path / "b.db"))
    server = loop.run_until_complete(broker.serve(path, group=None))
    return loop, server, path


def ask(loop, path, raw: bytes) -> dict:
    def go():
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.connect(path)
            s.sendall(raw)
            return json.loads(s.makefile("rb").readline())
    return loop.run_until_complete(asyncio.to_thread(go))


@pytest.fixture
def known(tmp_path):
    loop, server, path = serve(tmp_path, {ME: Agent(name="research", uid=ME)})
    yield loop, path
    server.close()
    loop.close()


def test_caller_is_identified_by_uid(known):
    loop, path = known
    assert ask(loop, path, b'{"op": "whoami", "agent": "assistant"}\n') == {
        "ok": True, "agent": "research", "admin": False}


def test_unknown_caller_refused(tmp_path):
    loop, server, path = serve(tmp_path, {ME + 1: Agent(name="assistant", uid=ME + 1)})
    assert ask(loop, path, b'{"op": "whoami"}\n') == {"ok": False, "error": "unknown_caller"}
    server.close()
    loop.close()


@pytest.mark.parametrize("raw", [b"not json\n", b'{"nop": 1}\n', b"[1]\n", b'{"op": 7}\n'])
def test_bad_request(known, raw):
    loop, path = known
    assert ask(loop, path, raw)["error"] in {"bad_request", "unknown_op"}


def test_unknown_op(known):
    loop, path = known
    assert ask(loop, path, b'{"op": "dump_tokens"}\n') == {"ok": False, "error": "unknown_op"}


def test_socket_mode(known):
    _, path = known
    assert os.stat(path).st_mode & 0o777 == 0o660


def test_client_call(known):
    loop, path = known
    resp = loop.run_until_complete(asyncio.to_thread(client.call, "whoami", path))
    assert resp["agent"] == "research"


def test_load_config(tmp_path):
    me = getpass.getuser()
    f = tmp_path / "c.toml"
    f.write_text(f'[agents.{me}]\nadmin = true\ncdp_port = 9222\n'
                 '[agents.no-such-user-here]\nadmin = true\n')
    c = load(f)
    assert c.agents == {ME: Agent(name=me, uid=ME, admin=True, cdp_port=9222)}
    assert c.leakcheck == Leakcheck(roots=("/home/*/.claude", "/var/lib/credbroker"), canary_file=None)
    assert c.mqtt == Mqtt(url=None, event_topic="credbroker/events", status_topic="credbroker/status",
                          ha_discovery=False)


def test_load_config_leakcheck(tmp_path):
    f = tmp_path / "c.toml"
    f.write_text('[leakcheck]\nroots = ["/srv/notes"]\ncanary_file = "/srv/notes/canary.jsonl"\n')
    assert load(f).leakcheck == Leakcheck(roots=("/srv/notes",), canary_file="/srv/notes/canary.jsonl")


def test_load_config_mqtt(tmp_path):
    f = tmp_path / "c.toml"
    f.write_text('[mqtt]\nurl = "mqtt://broker.example:1884"\nevent_topic = "site/events"\nha_discovery = true\n')
    assert load(f).mqtt == Mqtt(url="mqtt://broker.example:1884", event_topic="site/events",
                                status_topic="credbroker/status", ha_discovery=True)
    f.write_text('[mqtt]\nha_discovery = true\n')
    assert load(f).mqtt.url is None


def test_load_config_takes_mqtt_or_mqtts_urls_only(tmp_path):
    f = tmp_path / "c.toml"
    f.write_text('[mqtt]\nurl = "mqtts://broker.example"\n')
    assert load(f).mqtt.url == "mqtts://broker.example"
    f.write_text('[mqtt]\nurl = "broker.example:1883"\n')
    with pytest.raises(ValueError, match="mqtts://"):
        load(f)


@pytest.mark.parametrize("text", [
    f"[agents.{getpass.getuser()}]\npassword = 'x'\n",
    "[leakcheck]\nroot = []\n",
    "[mqtt]\nusername = 'u'\n",
    "[leakchek]\n",
])
def test_load_config_rejects_unknown_names(tmp_path, text):
    f = tmp_path / "c.toml"
    f.write_text(text)
    with pytest.raises(ValueError, match="unknown"):
        load(f)


def test_missing_config_file_names_the_path(tmp_path):
    with pytest.raises(SystemExit, match=str(tmp_path / "none.toml")):
        load(tmp_path / "none.toml")


def test_example_config_parses_with_mqtt_off():
    assert load(Path(__file__).parents[1] / "config.example.toml").mqtt.url is None


def test_broker_starts_and_serves_without_mqtt(tmp_path, monkeypatch):
    def no_bus(*a):
        raise AssertionError("MQTT is off: no connection should be made")
    monkeypatch.setattr(server, "Bus", no_bus)
    monkeypatch.setattr(server.config, "load", lambda: Config({ME: Agent(name="research", uid=ME)}))
    monkeypatch.setattr("credbroker.secretstore.load_secrets", lambda: {})
    monkeypatch.setattr(server.config, "DB_PATH", str(tmp_path / "b.db"))
    monkeypatch.setattr(server.config, "SOCKET_PATH", str(tmp_path / "b.sock"))
    monkeypatch.setattr(server.grp, "getgrnam", lambda name: grp.getgrgid(os.getgid()))

    async def go():
        task = asyncio.create_task(server.run())
        while not (tmp_path / "b.sock").exists() and not task.done():
            await asyncio.sleep(0.01)
        resp = await asyncio.to_thread(client.call, "whoami", str(tmp_path / "b.sock"))
        task.cancel()
        with pytest.raises(asyncio.CancelledError):
            await task
        return resp
    assert asyncio.run(go())["agent"] == "research"


def test_logins_lists_titles_and_websites_only(tmp_path):
    vault = StubVault([Login("id1", "Wiki", (Website("http://192.0.2.20:8080", "AnywhereOnWebsite"),))])
    loop, server, path = serve(tmp_path, {ME: Agent(name="research", uid=ME)}, {"research": vault})
    assert ask(loop, path, b'{"op": "logins"}\n') == {
        "ok": True, "logins": [{"title": "Wiki", "websites": ["http://192.0.2.20:8080"]}]}
    server.close()
    loop.close()


def test_logins_without_vault(known):
    loop, path = known
    assert ask(loop, path, b'{"op": "logins"}\n') == {"ok": False, "error": "no_vault"}


def test_logins_vault_error(tmp_path):
    loop, server, path = serve(tmp_path, {ME: Agent(name="research", uid=ME)}, {"research": StubVault(fail=True)})
    assert ask(loop, path, b'{"op": "logins"}\n') == {"ok": False, "error": "vault_unavailable"}
    server.close()
    loop.close()


@pytest.mark.parametrize("argv,expected", [
    (["whoami"], ("whoami", {})),
    (["approvals", "--all"], ("approvals", {"all": True})),
    (["revoke", "research", "Example", "Investments"], ("revoke", {"agent": "research", "login": "Example Investments"})),
])
def test_cli_parse(argv, expected):
    assert client.parse(argv) == expected


def test_cli_parse_rejects():
    with pytest.raises(SystemExit):
        client.parse(["revoke", "research"])
