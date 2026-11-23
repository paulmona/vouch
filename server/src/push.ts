import type { Approval } from "./approvals.ts";
import type { Device, Devices } from "./devices.ts";
import type { Fcm, PushData } from "./fcm.ts";
import type { Logger } from "./log.ts";

export interface Sender {
  send: Fcm["send"];
}

// Who gets which push. Sends never block the caller: the broker's create call
// returns at once, and a failed push shows up in the logs and, via
// fetched_at, in the timings.
export class Push {
  readonly #sender: Sender | null;
  readonly #devices: Devices;
  readonly #log: Logger;
  readonly #onSent: (requestId: string, at: string) => void;
  readonly #now: () => number;

  constructor(sender: Sender | null, devices: Devices, log: Logger,
    onSent: (requestId: string, at: string) => void, now: () => number = Date.now) {
    this.#sender = sender;
    this.#devices = devices;
    this.#log = log;
    this.#onSent = onSent;
    this.#now = now;
  }

  async request(a: Approval): Promise<void> {
    const ttl = (Date.parse(a.expires_at) - this.#now()) / 1000;
    const results = await this.#broadcast({ v: "1", kind: "request", request_id: a.request_id }, ttl, a.request_id);
    if (results.includes("sent")) this.#onSent(a.request_id, new Date(this.#now()).toISOString());
  }

  // Everyone but the device that answered (if one did) drops the request.
  async clear(a: Approval): Promise<void> {
    await this.#broadcast({ v: "1", kind: "clear", request_id: a.request_id }, 300, a.request_id, a.device_id);
  }

  async heartbeat(heartbeatId: string): Promise<void> {
    await this.#broadcast({ v: "1", kind: "heartbeat", heartbeat_id: heartbeatId }, 3600);
  }

  async alert(alertId: string, except: string | null = null): Promise<void> {
    await this.#broadcast({ v: "1", kind: "alert", alert_id: alertId }, 24 * 3600, null, except);
  }

  // Silent: a text was stored or sent; the app refetches its SMS views. No id
  // and no number goes through Firebase.
  async smsUpdated(): Promise<string[]> {
    return this.#broadcast({ v: "1", kind: "sms_updated" }, 300);
  }

  async #broadcast(data: PushData, ttl: number, requestId: string | null = null, except: string | null = null) {
    const targets = this.#devices.pushable().filter((d) => d.device_id !== except);
    if (!this.#sender) {
      if (targets.length) this.#log.warn({ kind: data.kind, request_id: requestId }, "push_disabled");
      return [];
    }
    return Promise.all(targets.map((d) => this.#one(d, data, ttl, requestId)));
  }

  async #one(d: Device, data: PushData, ttl: number, requestId: string | null) {
    const started = this.#now();
    const { result, detail } = await this.#sender!.send(d.push_token, data, ttl);
    const fields = { kind: data.kind, request_id: requestId, device_id: d.device_id, outcome: result, detail,
      latency_ms: this.#now() - started };
    if (result === "sent") this.#log.info(fields, "push_sent");
    else if (result === "invalid_token") {
      this.#devices.markPushInvalid(d.device_id);
      this.#log.warn(fields, "push_token_invalid");
    } else this.#log.error(fields, "push_failed");
    return result;
  }
}
