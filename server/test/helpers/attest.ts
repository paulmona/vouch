// Builds Android-style attestation chains with openssl, for tests only.
import { execFileSync } from "node:child_process";
import { generateKeyPairSync, randomBytes, sign, X509Certificate, type KeyObject } from "node:crypto";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { canonical } from "../../src/signing.ts";

function len(n: number): Buffer {
  if (n < 0x80) return Buffer.from([n]);
  const bytes: number[] = [];
  for (; n > 0; n >>= 8) bytes.unshift(n & 0xff);
  return Buffer.from([0x80 | bytes.length, ...bytes]);
}
const tlv = (tag: number[], body: Buffer) => Buffer.concat([Buffer.from(tag), len(body.length), body]);
const seq = (...items: Buffer[]) => tlv([0x30], Buffer.concat(items));
const int = (n: number) => tlv([0x02], Buffer.from(n < 0x80 ? [n] : [n >> 8, n & 0xff]));
const enumerated = (n: number) => tlv([0x0a], Buffer.from([n]));
const octets = (b: Buffer) => tlv([0x04], b);
// Context-specific, constructed, high tag number (all the tags used here are 128 to 16383).
const ctx = (tag: number, inner: Buffer) => tlv([0xbf, 0x80 | (tag >> 7), tag & 0x7f], inner);

export interface KeyOpts {
  challenge: Buffer;
  securityLevel?: 0 | 1 | 2;
  userAuthType?: number; // 0 to leave the tag out
  authTimeout?: number; // 0 to leave the tag out
  noAuthRequired?: boolean;
}

export function keyDescription(o: KeyOpts): Buffer {
  const level = o.securityLevel ?? 1;
  const hw: Buffer[] = [];
  if (o.noAuthRequired) hw.push(ctx(503, tlv([0x05], Buffer.alloc(0))));
  if (o.userAuthType) hw.push(ctx(504, int(o.userAuthType)));
  if (o.authTimeout) hw.push(ctx(505, int(o.authTimeout)));
  return seq(int(200), enumerated(level), int(200), enumerated(level), octets(o.challenge), octets(Buffer.alloc(0)), seq(), seq(...hw));
}

export interface Chain {
  chain: string[]; // leaf first, DER base64url
  rootKey: Buffer; // SPKI DER
}

export function deviceKey(): { privateKey: KeyObject; publicKey: string } {
  const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
  return { privateKey, publicKey: publicKey.export({ type: "spki", format: "der" }).toString("base64url") };
}

export function makeChain(leafKey: KeyObject, opts: KeyOpts): Chain {
  const d = mkdtempSync(join(tmpdir(), "vouch-att-"));
  const ssl = (...args: string[]) => execFileSync("openssl", args, { cwd: d, stdio: ["ignore", "pipe", "pipe"] });
  try {
    writeFileSync(join(d, "ca.cnf"), "basicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign\n");
    writeFileSync(join(d, "leaf.cnf"), `1.3.6.1.4.1.11129.2.1.17=DER:${keyDescription(opts).toString("hex")}\n`);
    writeFileSync(join(d, "leaf.key"), leafKey.export({ type: "pkcs8", format: "pem" }));
    const ec = ["-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:P-256", "-nodes"];
    ssl("req", "-x509", ...ec, "-keyout", "root.key", "-out", "root.pem", "-subj", "/CN=Test root", "-days", "30",
      "-addext", "basicConstraints=critical,CA:TRUE", "-addext", "keyUsage=critical,keyCertSign");
    ssl("req", "-new", ...ec, "-keyout", "int.key", "-out", "int.csr", "-subj", "/CN=Test intermediate");
    ssl("x509", "-req", "-in", "int.csr", "-CA", "root.pem", "-CAkey", "root.key", "-extfile", "ca.cnf", "-days", "30", "-out", "int.pem");
    ssl("req", "-new", "-key", "leaf.key", "-out", "leaf.csr", "-subj", "/CN=Android Keystore Key");
    ssl("x509", "-req", "-in", "leaf.csr", "-CA", "int.pem", "-CAkey", "int.key", "-extfile", "leaf.cnf", "-days", "30", "-out", "leaf.pem");
    const der = (f: string) => new X509Certificate(ssl("x509", "-in", f)).raw;
    const root = new X509Certificate(der("root.pem"));
    return { chain: ["leaf.pem", "int.pem", "root.pem"].map((f) => der(f).toString("base64url")),
      rootKey: root.publicKey.export({ type: "spki", format: "der" }) };
  } finally {
    rmSync(d, { recursive: true });
  }
}

export function signedHeaders(privateKey: KeyObject, method: string, target: string, body: string,
  timestamp = String(Math.floor(Date.now() / 1000)), nonce = randomBytes(16).toString("base64url")) {
  const sig = sign("sha256", Buffer.from(canonical(method, target, Buffer.from(body), timestamp, nonce)), { key: privateKey, dsaEncoding: "der" });
  return { "content-type": "application/json", "x-vouch-timestamp": timestamp, "x-vouch-nonce": nonce,
    "x-vouch-signature": sig.toString("base64url") };
}
