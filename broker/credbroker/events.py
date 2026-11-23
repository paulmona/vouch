"""MQTT, when the config file turns it on: one event per sign-in request, and a heartbeat.

The event schema is a contract with whatever consumes it; it carries no
usernames or passwords. The heartbeat is retained, with a retained "down" as the
last will. With `ha_discovery` it is also announced to Home Assistant as a
connectivity sensor that goes unavailable when it has not heard from the broker
for five minutes.
"""
from __future__ import annotations

import asyncio
import json
import logging
from datetime import UTC, datetime
from urllib.parse import urlparse

import paho.mqtt.client as mqtt

from .config import Mqtt

log = logging.getLogger("credbroker")

DISCOVERY_TOPIC = "homeassistant/binary_sensor/credbroker/config"
HEARTBEAT_S = 60
STALE_S = 300

EVENT_FIELDS = ("ts", "request_id", "agent", "login_id", "login_title", "site", "reason",
                "decision", "notify_ms", "decide_ms", "fill_ms", "result")


def discovery(status_topic: str) -> dict:
    return {
        "name": "Credential broker",
        "unique_id": "credbroker_heartbeat",
        "device_class": "connectivity",
        "state_topic": status_topic,
        "value_template": "{{ value_json.status }}",
        "payload_on": "up",
        "payload_off": "down",
        "expire_after": STALE_S,
    }


def now() -> str:
    return datetime.now(UTC).isoformat(timespec="seconds")


def event(row: dict) -> dict:
    """The published shape of one finished request, from its broker.db row."""
    return {k: row.get(k) for k in EVENT_FIELDS}


def status(state: str) -> str:
    return json.dumps({"status": state, "ts": now()})


def _client(client_id: str, url: str, secrets: dict[str, str]) -> mqtt.Client:
    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id=client_id)
    if secrets.get("MQTT_USERNAME"):
        client.username_pw_set(secrets["MQTT_USERNAME"], secrets.get("MQTT_PASSWORD"))
    if urlparse(url).scheme == "mqtts":
        client.tls_set()  # the system's CA certificates, and the server's name is checked
    return client


def _address(url: str) -> tuple[str, int]:
    u = urlparse(url)
    return u.hostname, u.port or (8883 if u.scheme == "mqtts" else 1883)


class Bus:
    def __init__(self, cfg: Mqtt, secrets: dict[str, str]):
        self._cfg = cfg
        self.client = _client("credbroker", cfg.url, secrets)
        self.client.will_set(cfg.status_topic, status("down"), qos=1, retain=True)
        self.client.reconnect_delay_set(1, 60)
        self.client.on_connect = self._on_connect

    def _on_connect(self, client, userdata, flags, reason_code, properties):
        if reason_code.is_failure:
            log.warning("mqtt connect failed: %s", reason_code)
            return
        if self._cfg.ha_discovery:
            client.publish(DISCOVERY_TOPIC, json.dumps(discovery(self._cfg.status_topic)), qos=1, retain=True)
        client.publish(self._cfg.status_topic, status("up"), qos=1, retain=True)

    def start(self) -> None:
        self.client.connect_async(*_address(self._cfg.url))
        self.client.loop_start()

    def emit(self, row: dict) -> None:
        payload = json.dumps(event(row))
        log.info("event %s", payload)
        self.client.publish(self._cfg.event_topic, payload, qos=1)

    async def heartbeat(self) -> None:
        while True:
            if self.client.is_connected():
                self.client.publish(self._cfg.status_topic, status("up"), qos=1, retain=True)
            await asyncio.sleep(HEARTBEAT_S)


def publish_once(cfg: Mqtt, secrets: dict[str, str], payload: dict) -> None:
    """Connect, publish one event and disconnect. For the leak check, which runs beside
    the broker: its own client id, so it does not take over the broker's connection."""
    client = _client("credbroker-leakcheck", cfg.url, secrets)
    client.connect(*_address(cfg.url))
    client.loop_start()
    try:
        client.publish(cfg.event_topic, json.dumps(payload), qos=1).wait_for_publish(10)
    finally:
        client.disconnect()
        client.loop_stop()
