// Everything provider-specific sits behind these four members. Keep it to four
// until a second provider exists to shape it.

export interface InboundMessage {
  from: string; // E.164
  to: string; // E.164, the agent's number
  text: string;
  providerId: string;
  at: string; // RFC 3339
}

export interface ProviderLimits {
  smsLength: number; // longest body sent as SMS
  mms: boolean; // can longer bodies go as text-only MMS?
  maxLength: number; // longest body the provider takes at all
}

export interface SmsProvider {
  readonly name: string;
  readonly limits: ProviderLimits;
  // Returns the provider's message id. `mms` is set when the body is over smsLength.
  send(to: string, text: string, mms: boolean): Promise<string>;
  // A webhook or MQTT body; null when it isn't a message for us.
  parseInbound(body: unknown): InboundMessage | null;
  listSince?(since: Date): Promise<InboundMessage[]>;
}
