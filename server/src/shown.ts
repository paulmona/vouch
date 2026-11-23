import { createHash } from "node:crypto";

// What a phone shows for a request, in the order the contract fixes. The phone
// sends the digest of what it displayed inside the signed decision, so an
// answer can't be moved to a request the owner never saw.
export interface Shown {
  request_id: string;
  kind: string;
  agent: string;
  site: string;
  login_title: string | null;
  expires_at: string;
  sms_contact?: { phone: string | null; name: string | null; reason: string | null };
}

// Each field is `name=<UTF-8 byte length>:<value>` or `name=-` for null, one per
// line: the length makes a value that contains a newline unambiguous.
export function shownCanonical(v: Shown): string {
  const fields: [string, string | null][] = [
    ["request_id", v.request_id], ["kind", v.kind], ["agent", v.agent], ["site", v.site],
    ["login_title", v.login_title], ["expires_at", v.expires_at],
    ["sms_phone", v.sms_contact?.phone ?? null], ["sms_name", v.sms_contact?.name ?? null],
    ["sms_reason", v.sms_contact?.reason ?? null],
  ];
  return "vouch-shown-v1\n" + fields.map(([name, value]) =>
    value === null ? `${name}=-\n` : `${name}=${Buffer.byteLength(value, "utf8")}:${value}\n`).join("");
}

export const shownDigest = (v: Shown): string => createHash("sha256").update(shownCanonical(v), "utf8").digest("hex");
