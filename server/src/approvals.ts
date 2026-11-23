import type { DatabaseSync } from "node:sqlite";
import type { Logger } from "./log.ts";

export type Kind = "sign_in" | "sms_contact";
export type State = "pending" | "once" | "always" | "deny" | "timeout" | "cancelled";

export interface Approval {
  request_id: string;
  kind: Kind;
  agent: string;
  site: string;
  login_title: string | null;
  created_at: string;
  expires_at: string;
  state: State;
  decided_at: string | null;
  device_id: string | null;
  push_sent_at: string | null;
  fetched_at: string | null;
  // Only for sms_contact: who the agent wants to text, and why.
  sms_phone: string | null;
  sms_name: string | null;
  sms_reason: string | null;
}

export type NewApproval = Pick<Approval, "request_id" | "kind" | "agent" | "site" | "login_title" | "expires_at"> &
  Partial<Pick<Approval, "sms_phone" | "sms_name" | "sms_reason">>;

// Called after the change is stored. They must not throw (push does its own logging).
export interface ApprovalHooks {
  created?(a: Approval): void;
  settled?(a: Approval): void;
}

const RETENTION_MS = 7 * 24 * 3600 * 1000;

// Every move out of `pending` goes through settle(), whose UPDATE only matches a
// pending row: whichever of a decision, a cancel or the expiry timer gets there
// first wins, and the others see the final state.
export class Approvals {
  readonly #db: DatabaseSync;
  readonly #log: Logger;
  readonly #now: () => number;
  readonly #waiters = new Map<string, Set<() => void>>();
  readonly #timers = new Map<string, NodeJS.Timeout>();
  #purge: NodeJS.Timeout | undefined;
  hooks: ApprovalHooks = {};

  constructor(db: DatabaseSync, log: Logger, now: () => number = Date.now) {
    this.#db = db;
    this.#log = log;
    this.#now = now;
  }

  // Newest first; only requests still open to an answer.
  pending(limit: number): Approval[] {
    return this.#db.prepare(`SELECT * FROM approvals WHERE state = 'pending' AND expires_at > ?
      ORDER BY created_at DESC LIMIT ?`).all(this.#iso(), limit) as unknown as Approval[];
  }

  pendingOfKind(kind: Kind): Approval[] {
    return this.#db.prepare(`SELECT * FROM approvals WHERE state = 'pending' AND kind = ? AND expires_at > ?
      ORDER BY created_at`).all(kind, this.#iso()) as unknown as Approval[];
  }

  // A device's first fetch of a request is its push-to-screen moment.
  recordFetch(id: string, deviceId: string): void {
    const at = this.#iso();
    const first = this.#db.prepare("INSERT OR IGNORE INTO request_fetches (request_id, device_id, fetched_at) VALUES (?, ?, ?)")
      .run(id, deviceId, at).changes === 1;
    if (!first) return;
    this.#db.prepare("UPDATE approvals SET fetched_at = ? WHERE request_id = ? AND fetched_at IS NULL").run(at, id);
    const a = this.get(id)!;
    this.#log.info({ request_id: id, kind: a.kind, agent: a.agent, device_id: deviceId,
      latency_ms: a.push_sent_at ? Date.parse(at) - Date.parse(a.push_sent_at) : null }, "request_fetched");
  }

  // Expiry runs on a timer; this closes the gap between expires_at and the timer firing.
  expireIfDue(id: string): void {
    const a = this.get(id);
    if (a?.state === "pending" && Date.parse(a.expires_at) <= this.#now()) this.settle(id, "timeout");
  }

  markPushSent(id: string, at: string): void {
    this.#db.prepare("UPDATE approvals SET push_sent_at = ? WHERE request_id = ? AND push_sent_at IS NULL").run(at, id);
  }

  // Expire what ran out while the service was down, re-arm the rest.
  start(): void {
    const pending = this.#db.prepare("SELECT request_id, expires_at FROM approvals WHERE state = 'pending'").all() as
      Pick<Approval, "request_id" | "expires_at">[];
    for (const a of pending) this.#arm(a.request_id, a.expires_at);
    this.purge();
    this.#purge = setInterval(() => this.purge(), 3600 * 1000).unref();
  }

  stop(): void {
    clearInterval(this.#purge);
    for (const t of this.#timers.values()) clearTimeout(t);
    this.#timers.clear();
    for (const id of [...this.#waiters.keys()]) this.#wake(id);
  }

  get(id: string): Approval | undefined {
    return this.#db.prepare("SELECT * FROM approvals WHERE request_id = ?").get(id) as Approval | undefined;
  }

  // Creating the same request twice (a broker retry) is fine; reusing its id for a
  // different request is not.
  create(a: NewApproval): { approval: Approval; created: boolean } | { conflict: Approval } {
    const existing = this.get(a.request_id);
    if (existing) {
      const same = existing.kind === a.kind && existing.agent === a.agent && existing.site === a.site &&
        existing.login_title === a.login_title && existing.expires_at === a.expires_at;
      return same ? { approval: existing, created: false } : { conflict: existing };
    }
    this.#db.prepare(`INSERT INTO approvals (request_id, kind, agent, site, login_title, created_at, expires_at,
        sms_phone, sms_name, sms_reason) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
      .run(a.request_id, a.kind, a.agent, a.site, a.login_title, this.#iso(), a.expires_at,
        a.sms_phone ?? null, a.sms_name ?? null, a.sms_reason ?? null);
    this.#log.info({ request_id: a.request_id, kind: a.kind, agent: a.agent, site: a.site }, "approval_created");
    this.#arm(a.request_id, a.expires_at);
    const approval = this.get(a.request_id)!;
    this.hooks.created?.(approval);
    return { approval, created: true };
  }

  // Resolves with the approval once it leaves `pending`, or after `seconds`.
  async wait(id: string, seconds: number): Promise<Approval | undefined> {
    const a = this.get(id);
    if (!a || a.state !== "pending" || seconds <= 0) return a;
    await new Promise<void>((resolve) => {
      const done = () => {
        clearTimeout(timer);
        this.#waiters.get(id)?.delete(done);
        resolve();
      };
      const timer = setTimeout(done, seconds * 1000);
      let set = this.#waiters.get(id);
      if (!set) this.#waiters.set(id, (set = new Set()));
      set.add(done);
    });
    return this.get(id);
  }

  cancel(id: string): Approval | undefined {
    this.settle(id, "cancelled");
    return this.get(id);
  }

  // Returns true only for the call that moved the approval out of `pending`.
  settle(id: string, state: Exclude<State, "pending">, deviceId: string | null = null): boolean {
    const decidedAt = this.#iso();
    const r = this.#db.prepare(`UPDATE approvals SET state = ?, decided_at = ?, device_id = ?
      WHERE request_id = ? AND state = 'pending'`).run(state, decidedAt, deviceId, id);
    if (r.changes !== 1) return false;
    clearTimeout(this.#timers.get(id));
    this.#timers.delete(id);
    const a = this.get(id)!;
    this.#log.info({ request_id: id, kind: a.kind, agent: a.agent, device_id: deviceId, outcome: state,
      latency_ms: Date.parse(decidedAt) - Date.parse(a.created_at) }, "approval_settled");
    this.#wake(id);
    this.hooks.settled?.(a);
    return true;
  }

  purge(): number {
    const cutoff = new Date(this.#now() - RETENTION_MS).toISOString();
    const r = this.#db.prepare("DELETE FROM approvals WHERE state != 'pending' AND created_at < ?").run(cutoff);
    return Number(r.changes);
  }

  #arm(id: string, expiresAt: string): void {
    const ms = Date.parse(expiresAt) - this.#now();
    if (ms <= 0) {
      this.settle(id, "timeout");
      return;
    }
    clearTimeout(this.#timers.get(id));
    // unref: the listeners keep a running service alive; a pending expiry should not.
    this.#timers.set(id, setTimeout(() => this.settle(id, "timeout"), ms).unref());
  }

  #wake(id: string): void {
    const set = this.#waiters.get(id);
    this.#waiters.delete(id);
    for (const done of set ?? []) done();
  }

  #iso(): string {
    return new Date(this.#now()).toISOString();
  }
}
