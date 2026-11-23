import json

from credbroker import events
from credbroker.config import Mqtt
from credbroker.events import EVENT_FIELDS, Bus, event
from credbroker.store import Store


def test_event_has_every_field_and_nothing_else(tmp_path):
    s = Store(tmp_path / "b.db")
    rid = s.start_request("research", "https://portal.example.com", "check balance")
    s.update_request(rid, login_id="a", login_title="Example", decision="once",
                     notify_ms=150, decide_ms=4000, fill_ms=2100, result="signed_in")
    e = event(s.get_request(rid))
    assert tuple(e) == EVENT_FIELDS
    assert e["request_id"] == rid and e["result"] == "signed_in"


def test_event_of_unfinished_request_keeps_nulls(tmp_path):
    s = Store(tmp_path / "b.db")
    e = event(s.get_request(s.start_request("research", "https://x", "r")))
    assert e["decision"] is None and set(e) == set(EVENT_FIELDS)


class FakeClient:
    def __init__(self):
        self.published = []

    def publish(self, topic, payload, qos=0, retain=False):
        self.published.append((topic, payload, qos, retain))


class RC:
    is_failure = False


def test_connect_marks_up_on_the_default_topic_without_discovery():
    bus = Bus(Mqtt(url="mqtt://broker:1883"), {})
    c = FakeClient()
    bus._on_connect(c, None, None, RC(), None)
    ((topic, payload, _, retain),) = c.published
    assert (topic, retain) == ("credbroker/status", True) and json.loads(payload)["status"] == "up"


def test_connect_announces_the_sensor_when_ha_discovery_is_on():
    bus = Bus(Mqtt(url="mqtt://broker:1883", status_topic="site/status", ha_discovery=True), {})
    c = FakeClient()
    bus._on_connect(c, None, None, RC(), None)
    (t1, p1, _, r1), (t2, _, _, r2) = c.published
    assert (t1, r1) == (events.DISCOVERY_TOPIC, True) and (t2, r2) == ("site/status", True)
    d = json.loads(p1)
    assert d["state_topic"] == "site/status" and d["unique_id"] == "credbroker_heartbeat"


def test_emit_publishes_event_not_retained():
    bus = Bus(Mqtt(url="mqtt://broker:1883", event_topic="site/events"), {"MQTT_USERNAME": "u", "MQTT_PASSWORD": "p"})
    bus.client = FakeClient()
    bus.emit({"request_id": "r1", "agent": "research", "password": "never"})
    ((topic, payload, qos, retain),) = bus.client.published
    assert (topic, qos, retain) == ("site/events", 1, False)
    assert "password" not in json.loads(payload)


def test_login_is_used_only_when_given():
    assert Bus(Mqtt(url="mqtt://broker"), {}).client.username is None
    c = Bus(Mqtt(url="mqtt://broker"), {"MQTT_USERNAME": "u", "MQTT_PASSWORD": "p"}).client
    assert (c.username, c.password) == ("u", "p")


def test_mqtts_turns_tls_on_and_defaults_to_8883(monkeypatch):
    tls = []
    monkeypatch.setattr(events.mqtt.Client, "tls_set", lambda self, *a, **k: tls.append(True))
    events._client("c", "mqtts://broker.example", {})
    assert tls == [True] and events._address("mqtts://broker.example") == ("broker.example", 8883)
    events._client("c", "mqtt://broker.example", {})
    assert tls == [True] and events._address("mqtt://broker.example") == ("broker.example", 1883)
