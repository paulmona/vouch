import { randomBytes } from "node:crypto";
import type { DatabaseSync } from "node:sqlite";
import type { Logger } from "./log.ts";
import type { Push } from "./push.ts";

export interface HeartbeatConfig {
  intervalHours: number;
  silentAfterHours: number;
}

const HOUR = 3600 * 1000;
const RETENTION_MS = 30 * 24 * HOUR;

// With no MQTT in the approver, the phones are the monitor: a daily push that
// each phone answers over the tunnel proves the whole path, and a phone that
// stops answering is reported.
export class Heartbeat {
  readonly #db: DatabaseSync;
  readonly #push: Pick<Push, "heartbeat">;
  readonly #log: Logger;
  readonly #cfg: HeartbeatConfig;
  readonly #now: () => number;
  #timer: NodeJS.Timeout | undefined;

  constructor(db: DatabaseSync, push: Pick<Push, "heartbeat">, log: Logger, cfg: HeartbeatConfig, now: () => number = Date.now) {
    this.#db = db;
    this.#push = push;
    this.#log = log;
    this.#cfg = cfg;
    this.#now = now;
  }

  // Checks hourly; the last send is in the database, so restarts do not resend.
  start(): void {
    void this.tick();
    this.#timer = setInterval(() => void this.tick(), HOUR).unref();
  }

  stop(): void {
    clearInterval(this.#timer);
  }

  async tick(): Promise<void> {
    const last = this.#db.prepare("SELECT max(sent_at) AS at FROM heartbeats").get() as { at: string | null };
    if (!last.at || this.#now() - Date.parse(last.at) >= this.#cfg.intervalHours * HOUR - 60_000) await this.send();
    this.#findSilent();
    this.#db.prepare("DELETE FROM heartbeats WHERE sent_at < ?").run(this.#iso(this.#now() - RETENTION_MS));
  }

  async send(): Promise<string> {
    const id = `hb_${randomBytes(9).toString("base64url")}`;
    this.#db.prepare("INSERT INTO heartbeats (heartbeat_id, sent_at) VALUES (?, ?)").run(id, this.#iso());
    this.#log.info({ heartbeat_id: id }, "heartbeat_sent");
    await this.#push.heartbeat(id);
    return id;
  }

  // An app-open check-in carries no heartbeat id; both count as contact.
  checkIn(deviceId: string, heartbeatId: string | null): void {
    const at = this.#iso();
    this.#db.prepare("UPDATE devices SET last_checkin_at = ?, silent_since = NULL WHERE device_id = ?").run(at, deviceId);
    if (!heartbeatId) return;
    const hb = this.#db.prepare("SELECT sent_at FROM heartbeats WHERE heartbeat_id = ?").get(heartbeatId) as { sent_at: string } | undefined;
    if (!hb) return;
    const first = this.#db.prepare("INSERT OR IGNORE INTO heartbeat_replies (heartbeat_id, device_id, replied_at) VALUES (?, ?, ?)")
      .run(heartbeatId, deviceId, at).changes === 1;
    if (first) {
      this.#log.info({ heartbeat_id: heartbeatId, device_id: deviceId, latency_ms: Date.parse(at) - Date.parse(hb.sent_at) },
        "heartbeat_reply");
    }
  }

  // A phone with no push token is left out: it is in touch only when its owner opens the app.
  #findSilent(): void {
    const cutoff = this.#iso(this.#now() - this.#cfg.silentAfterHours * HOUR);
    const silent = this.#db.prepare(`SELECT device_id, name, coalesce(last_checkin_at, paired_at) AS last_contact FROM devices
      WHERE revoked_at IS NULL AND silent_since IS NULL AND push_token != '' AND coalesce(last_checkin_at, paired_at) < ?`).all(cutoff) as
      { device_id: string; name: string; last_contact: string }[];
    for (const d of silent) {
      this.#db.prepare("UPDATE devices SET silent_since = ? WHERE device_id = ?").run(this.#iso(), d.device_id);
      this.#log.warn({ device_id: d.device_id, last_contact: d.last_contact, silent_after_hours: this.#cfg.silentAfterHours },
        "device_silent");
    }
  }

  #iso(ms = this.#now()): string {
    return new Date(ms).toISOString();
  }
}
