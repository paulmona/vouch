import type { DatabaseSync } from "node:sqlite";
import type { Logger } from "./log.ts";

export type Severity = "info" | "warning" | "critical";
export interface Alert { alert_id: string; severity: Severity; title: string; body: string; created_at: string }
export type NewAlert = Omit<Alert, "created_at">;

const RETENTION_MS = 30 * 24 * 3600 * 1000;
// A caller stuck in a loop must not bury the phone in notifications.
const MAX_PER_HOUR = 10;

export class Alerts {
  readonly #db: DatabaseSync;
  readonly #log: Logger;
  readonly #now: () => number;
  created: (a: Alert) => void = () => {};

  constructor(db: DatabaseSync, log: Logger, now: () => number = Date.now) {
    this.#db = db;
    this.#log = log;
    this.#now = now;
  }

  // Repeating the same alert is safe (a retry); the same id with other text is refused.
  create(n: NewAlert): { alert: Alert } | { refused: "conflict" | "too_many" } {
    const existing = this.get(n.alert_id);
    if (existing) {
      const same = existing.severity === n.severity && existing.title === n.title && existing.body === n.body;
      return same ? { alert: existing } : { refused: "conflict" };
    }
    const hourAgo = new Date(this.#now() - 3600 * 1000).toISOString();
    const recent = this.#db.prepare("SELECT count(*) AS n FROM alerts WHERE created_at > ?").get(hourAgo) as { n: number };
    if (recent.n >= MAX_PER_HOUR) {
      this.#log.warn({ alert_id: n.alert_id }, "alert_refused_too_many");
      return { refused: "too_many" };
    }
    const alert: Alert = { ...n, created_at: new Date(this.#now()).toISOString() };
    this.#db.prepare("INSERT INTO alerts (alert_id, severity, title, body, created_at) VALUES (?, ?, ?, ?, ?)")
      .run(alert.alert_id, alert.severity, alert.title, alert.body, alert.created_at);
    // The text can name logins and files, so only the id and severity are logged.
    this.#log.info({ alert_id: alert.alert_id, severity: alert.severity }, "alert_created");
    this.created(alert);
    return { alert };
  }

  get(id: string): Alert | undefined {
    return this.#db.prepare("SELECT alert_id, severity, title, body, created_at FROM alerts WHERE alert_id = ?").get(id) as
      Alert | undefined;
  }

  // Newest first. Purging keeps this to the last 30 days; the cap is a backstop.
  recent(limit = 100): Alert[] {
    return this.#db.prepare("SELECT alert_id, severity, title, body, created_at FROM alerts ORDER BY created_at DESC, alert_id LIMIT ?")
      .all(limit) as unknown as Alert[];
  }

  purge(): void {
    this.#db.prepare("DELETE FROM alerts WHERE created_at < ?").run(new Date(this.#now() - RETENTION_MS).toISOString());
  }
}
