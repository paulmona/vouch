import type { Logger } from "../log.ts";

// after a text is stored, tell the phones to refetch. Texts that land
// within `windowMs` of each other share one push. The latency logged is from
// the first stored text to the push being handed to Firebase (the aim is under 10 s at p95).
export class SmsUpdates {
  readonly #send: () => Promise<string[]>;
  readonly #log: Logger;
  readonly #windowMs: number;
  readonly #now: () => number;
  #pendingSince: number | null = null;

  constructor(send: () => Promise<string[]>, log: Logger, windowMs = 500, now: () => number = Date.now) {
    this.#send = send;
    this.#log = log;
    this.#windowMs = windowMs;
    this.#now = now;
  }

  stored(): void {
    if (this.#pendingSince !== null) return;
    this.#pendingSince = this.#now();
    setTimeout(() => void this.#flush(), this.#windowMs).unref();
  }

  async #flush(): Promise<void> {
    const since = this.#pendingSince!;
    this.#pendingSince = null;
    try {
      const results = await this.#send();
      this.#log.info({ devices: results.length, sent: results.filter((r) => r === "sent").length,
        latency_ms: this.#now() - since }, "sms_updated_push");
    } catch (err) {
      this.#log.error({ err: (err as Error).message }, "sms_updated_push_failed");
    }
  }
}
