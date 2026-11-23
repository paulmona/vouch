import type { Logger } from "../log.ts";
import { BadNumber, normalize } from "./phone.ts";
import type { SmsProvider } from "./provider.ts";
import type { SmsStore } from "./store.ts";

// The sending rules, the same for every provider.
export interface SendRules {
  ownerPhone: string; // E.164; the owner needs no approval and has their own cap
  dailyCap: number; // to everyone but the owner, rolling 24 h
  ownerDailyCap: number;
  intro: string; // prefixed when the agent hasn't texted a number for introGapDays
  introMarker: string; // if the text already contains this in its first 60 characters, no intro
  introGapDays: number;
  maxText: number;
}

export type RefusalCode = "invalid" | "not_approved" | "daily_cap" | "provider" | "not_available" | "too_many_pending";

// A policy refusal: a normal outcome the agent reads, not a crash.
export class Refused extends Error {
  readonly code: RefusalCode;

  constructor(code: RefusalCode, message: string) {
    super(message);
    this.code = code;
  }
}

const DAY_MS = 24 * 3600 * 1000;

export class Sender {
  private readonly provider: SmsProvider;
  private readonly store: SmsStore;
  private readonly rules: SendRules;
  private readonly log: Logger;
  private readonly now: () => Date;
  private readonly onStored: () => void;

  constructor(provider: SmsProvider, store: SmsStore, rules: SendRules, log: Logger, now: () => Date = () => new Date(),
    onStored: () => void = () => {}) {
    this.provider = provider;
    this.store = store;
    this.rules = rules;
    this.log = log;
    this.now = now;
    this.onStored = onStored;
  }

  async send(rawTo: string, rawText: string): Promise<{ to: string; text: string; messageId: string }> {
    let to: string;
    try {
      to = normalize(rawTo);
    } catch (e) {
      if (e instanceof BadNumber) throw new Refused("invalid", e.message);
      throw e;
    }
    let text = rawText.trim();
    if (!text) throw new Refused("invalid", "The message is empty.");
    const owner = to === this.rules.ownerPhone;
    if (!owner) {
      if (this.store.contactName(to) === null) {
        throw new Refused("not_approved", `${to} is not a permitted contact; ask for approval first.`);
      }
      const last = this.store.lastSentTo(to);
      const stale = last === null || this.now().getTime() - Date.parse(last) > this.rules.introGapDays * DAY_MS;
      const introduced = this.rules.introMarker !== "" && text.slice(0, 60).toLowerCase().includes(this.rules.introMarker.toLowerCase());
      if (this.rules.intro && stale && !introduced) {
        text = this.rules.intro + text;
      }
    }
    const max = Math.min(this.rules.maxText, this.provider.limits.maxLength);
    if (text.length > max) throw new Refused("invalid", `The message is longer than ${max} characters.`);
    const mms = text.length > this.provider.limits.smsLength;
    if (mms && !this.provider.limits.mms) {
      throw new Refused("invalid", `The message is longer than ${this.provider.limits.smsLength} characters.`);
    }

    const since = new Date(this.now().getTime() - DAY_MS).toISOString();
    const [cap, sent] = owner
      ? [this.rules.ownerDailyCap, this.store.sentSince(since, { only: to })]
      : [this.rules.dailyCap, this.store.sentSince(since, { except: this.rules.ownerPhone })];
    if (sent >= cap) throw new Refused("daily_cap", `The daily cap of ${cap} texts is reached; the owner can raise it.`);

    const at = this.now().toISOString();
    const base = { phone: to, direction: "outbound" as const, text, at, provider: this.provider.name };
    let providerId: string;
    try {
      providerId = await this.provider.send(to, text, mms);
    } catch (e) {
      this.store.record({ ...base, status: "failed", provider_id: null });
      this.onStored();
      this.log.warn({ direction: "outbound", provider: this.provider.name, outcome: "provider_error",
        err: (e as Error).message }, "sms_send");
      throw new Refused("provider", (e as Error).message);
    }
    const messageId = this.store.record({ ...base, status: "sent", provider_id: providerId })!;
    this.onStored();
    this.log.info({ message_id: messageId, direction: "outbound", provider: this.provider.name, outcome: "sent", mms },
      "sms_send");
    return { to, text, messageId };
  }
}
