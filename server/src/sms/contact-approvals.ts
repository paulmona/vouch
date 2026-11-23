import { randomBytes } from "node:crypto";
import type { Approval, Approvals } from "../approvals.ts";
import type { Logger } from "../log.ts";
import { oneLine } from "../text.ts";
import { Refused } from "./sender.ts";
import type { SmsStore } from "./store.ts";

// an agent asks to text someone new. That becomes an sms_contact approval,
// pushed to the owner's phones like a sign-in; the owner approves with Face ID
// or fingerprint (the decision key) instead of replying with an SMS code. An
// approval adds the contact; any outcome is told to the agent on its inbox.
export class ContactApprovals {
  readonly #approvals: Approvals;
  readonly #store: SmsStore;
  readonly #opts: { ownerPhone: string; ownerName: string; agentName: string; ttlHours: number; maxPending: number };
  readonly #notify: (text: string) => void;
  readonly #log: Logger;
  readonly #now: () => number;

  constructor(approvals: Approvals, store: SmsStore,
    opts: { ownerPhone: string; ownerName: string; agentName: string; ttlHours: number; maxPending: number },
    notify: (text: string) => void, log: Logger, now: () => number = Date.now) {
    this.#approvals = approvals;
    this.#store = store;
    this.#opts = opts;
    this.#notify = notify;
    this.#log = log;
    this.#now = now;
  }

  pending(): { phone: string; name: string; reason: string; expires_at: string }[] {
    return this.#approvals.pendingOfKind("sms_contact")
      .map((a) => ({ phone: a.sms_phone!, name: a.sms_name!, reason: a.sms_reason!, expires_at: a.expires_at }));
  }

  // `phone` is already E.164.
  async request(phone: string, rawName: string, rawReason: string): Promise<Record<string, unknown>> {
    const name = rawName.trim().slice(0, 64);
    const reason = rawReason.trim().slice(0, 500);
    if (!name || !reason) throw new Refused("invalid", "name and reason are required");
    if (!oneLine(name) || !oneLine(reason)) {
      throw new Refused("invalid", "name and reason must each be one line of visible text, with no control or invisible characters");
    }
    if (phone === this.#opts.ownerPhone || this.#store.contactName(phone) !== null) return { already_approved: true, phone };
    const waiting = this.#approvals.pendingOfKind("sms_contact");
    if (waiting.some((a) => a.sms_phone === phone)) {
      return { pending: true, phone, note: `already waiting on ${this.#opts.ownerName}` };
    }
    if (waiting.length >= this.#opts.maxPending) {
      throw new Refused("too_many_pending", `too many approvals already waiting on ${this.#opts.ownerName}`);
    }
    const r = this.#approvals.create({ request_id: `sms_${randomBytes(12).toString("base64url")}`, kind: "sms_contact",
      agent: this.#opts.agentName, site: phone, login_title: null,
      expires_at: new Date(this.#now() + this.#opts.ttlHours * 3600 * 1000).toISOString(),
      sms_phone: phone, sms_name: name, sms_reason: reason });
    if ("conflict" in r) throw new Error("request id collision");
    return { pending: true, phone, request_id: r.approval.request_id,
      note: `${this.#opts.ownerName} has been asked in Vouch; you will hear back in your inbox` };
  }

  // Wired to Approvals.hooks.settled. Must not throw.
  settled(a: Approval): void {
    if (a.kind !== "sms_contact") return;
    const who = `${a.sms_name} at ${a.sms_phone}`;
    try {
      if (a.state === "once") {
        this.#store.addContact({ phone: a.sms_phone!, name: a.sms_name!, added_at: a.decided_at!, added_by: "agent_request",
          device_id: a.device_id, request_id: a.request_id });
        this.#notify(`${this.#opts.ownerName} approved texting ${who}. You can send_sms to them now.`);
      } else if (a.state === "deny") {
        this.#notify(`${this.#opts.ownerName} refused texting ${who}. Do not text them.`);
      } else {
        this.#notify(`${this.#opts.ownerName} didn't answer the request to text ${who} in time. Do not text them; ` +
          "ask again only if they still want it.");
      }
      this.#log.info({ request_id: a.request_id, outcome: a.state, phone_last4: a.sms_phone?.slice(-4) }, "sms_contact_request");
    } catch (err) {
      this.#log.error({ request_id: a.request_id, err: (err as Error).message }, "sms_contact_request_failed");
    }
  }
}
