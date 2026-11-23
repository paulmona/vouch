import type { SmsConfig } from "../config.ts";
import type { SmsProvider } from "./provider.ts";
import { Voipms } from "./voipms.ts";

// [sms] provider picks one. Adding a provider is one module and one line here.
export function createProvider(sms: SmsConfig, env: Record<string, string | undefined> = process.env): SmsProvider {
  switch (sms.provider) {
    case "voipms":
      return new Voipms(sms.voipms, env);
    default:
      throw new Error(`unknown sms.provider "${sms.provider}"`);
  }
}
