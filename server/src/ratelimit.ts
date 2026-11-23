// Fixed-window counters in memory. Enough for one approver process; the limits
// are a brake on abuse through the tunnel, not an accounting system.
export class RateLimiter {
  readonly #limit: number;
  readonly #windowMs: number;
  readonly #now: () => number;
  readonly #windows = new Map<string, { count: number; resetAt: number }>();

  constructor(limit: number, windowMs: number, now: () => number = Date.now) {
    this.#limit = limit;
    this.#windowMs = windowMs;
    this.#now = now;
  }

  // Seconds to wait when over the limit, otherwise 0.
  hit(key: string): number {
    const now = this.#now();
    let w = this.#windows.get(key);
    if (!w || w.resetAt <= now) {
      if (this.#windows.size > 10_000) this.#sweep(now);
      w = { count: 0, resetAt: now + this.#windowMs };
      this.#windows.set(key, w);
    }
    w.count++;
    return w.count > this.#limit ? Math.max(1, Math.ceil((w.resetAt - now) / 1000)) : 0;
  }

  #sweep(now: number): void {
    for (const [k, w] of this.#windows) if (w.resetAt <= now) this.#windows.delete(k);
  }
}
