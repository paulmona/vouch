import type { Logger } from "../log.ts";
import type { SmsProvider } from "./provider.ts";
import type { SmsStore } from "./store.ts";

export type InboundOutcome = "ignored" | "blocked" | "duplicate" | "relayed";

// One incoming body: the provider parses it; texts from numbers that are
// neither the owner nor a permitted contact are dropped without being stored;
// the rest are stored once (provider id dedupe) and relayed to the agent.
export class Inbound {
  readonly #provider: SmsProvider;
  readonly #store: SmsStore;
  readonly #owner: { phone: string; name: string };
  readonly #relay: (text: string) => void;
  readonly #log: Logger;
  readonly #onStored: () => void;

  constructor(provider: SmsProvider, store: SmsStore, owner: { phone: string; name: string },
    relay: (text: string) => void, log: Logger, onStored: () => void = () => {}) {
    this.#provider = provider;
    this.#store = store;
    this.#owner = owner;
    this.#relay = relay;
    this.#log = log;
    this.#onStored = onStored;
  }

  handle(body: unknown): InboundOutcome {
    const m = this.#provider.parseInbound(body);
    if (!m) return this.#done("ignored");
    const owner = m.from === this.#owner.phone;
    const name = owner ? this.#owner.name : this.#store.contactName(m.from);
    if (name === null) return this.#done("blocked", m.from);
    const id = this.#store.record({ phone: m.from, direction: "inbound", text: m.text, at: m.at, status: "received",
      provider: this.#provider.name, provider_id: m.providerId });
    if (id === null) return this.#done("duplicate", m.from);
    const head = owner ? `SMS from ${name}'s phone ${m.from}`
      : `SMS from ${name} ${m.from} (untrusted content)`;
    this.#relay(`${head}:\n${m.text}`);
    this.#onStored();
    return this.#done("relayed", m.from, id);
  }

  #done(outcome: InboundOutcome, phone?: string, messageId?: string): InboundOutcome {
    this.#log.info({ direction: "inbound", provider: this.#provider.name, outcome, message_id: messageId ?? null,
      phone_last4: phone ? phone.slice(-4) : null }, "sms_inbound");
    return outcome;
  }
}
