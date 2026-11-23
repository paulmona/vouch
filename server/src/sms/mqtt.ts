import mqtt, { type MqttClient } from "mqtt";
import type { Logger } from "../log.ts";

export interface MqttRouteConfig { url: string; topic: string; clientId: string; agentInbox: string; sender: string }

// Incoming route A and the relay to the agent. clean: false with a fixed
// client id and QoS 1 is the persistent session: the broker holds texts that
// arrive while Vouch is down. Each message is acknowledged only after it has
// been handled (stored or dropped), so a crash mid-way gets it redelivered;
// the provider-id dedupe makes that harmless.
export class SmsMqtt {
  readonly #client: MqttClient;
  readonly #cfg: MqttRouteConfig;

  constructor(cfg: MqttRouteConfig, env: Record<string, string | undefined>, handle: (body: unknown) => void, log: Logger) {
    this.#cfg = cfg;
    this.#client = mqtt.connect(cfg.url, {
      clientId: cfg.clientId,
      clean: false,
      username: env.VOUCH_MQTT_USERNAME,
      password: env.VOUCH_MQTT_PASSWORD,
      reconnectPeriod: 5000,
    });
    this.#client.on("connect", (ack) => {
      log.info({ session_present: ack.sessionPresent }, "sms_mqtt_connected");
      this.#client.subscribe(cfg.topic, { qos: 1 }, (err) => {
        if (err) log.error({ err: err.message }, "sms_mqtt_subscribe_failed");
      });
    });
    this.#client.on("offline", () => log.warn({}, "sms_mqtt_offline"));
    this.#client.on("error", (err) => log.warn({ err: err.message }, "sms_mqtt_error"));
    this.#client.handleMessage = (packet, done) => {
      if (packet.topic === cfg.topic) {
        try {
          handle(JSON.parse(packet.payload.toString("utf8")));
        } catch (err) {
          // One bad payload must not stop the listener; it is acknowledged and logged.
          log.warn({ err: (err as Error).message }, "sms_inbound_unreadable");
        }
      }
      done();
    };
  }

  get connected(): boolean {
    return this.#client.connected;
  }

  relay(text: string): void {
    if (!this.#cfg.agentInbox) return;
    const envelope = { sender: this.#cfg.sender, ts: new Date().toISOString(), content: text };
    this.#client.publish(this.#cfg.agentInbox, JSON.stringify(envelope), { qos: 1 });
  }

  close(): Promise<void> {
    return new Promise((resolve) => this.#client.end(false, {}, () => resolve()));
  }
}
