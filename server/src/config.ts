import { readFileSync } from "node:fs";
import { hostname } from "node:os";
import { parse } from "smol-toml";
import { isIPv4, isIPv6 } from "node:net";

export interface Config {
  server: { name: string };
  app: { host: string; port: number; publicUrl: string; trustedProxies: string[] };
  policy: { requireUserAuth: boolean };
  sockets: { broker: string; brokerGroup: string; admin: string; sms: string; smsGroup: string };
  store: { path: string };
  log: { level: string };
  firebase: { serviceAccountFile: string };
  heartbeat: { intervalHours: number; silentAfterHours: number };
  modules: Modules;
  sms: SmsConfig;
}

export interface SmsConfig {
  provider: string;
  ownerPhone: string;
  dailyCap: number;
  ownerDailyCap: number;
  intro: string;
  introMarker: string;
  introGapDays: number;
  maxText: number;
  voipms: { did: string };
  ownerName: string;
  agentName: string;
  approvalTtlHours: number;
  maxPendingApprovals: number;
  mqtt: { url: string; topic: string; clientId: string; agentInbox: string; sender: string };
}

export interface Modules { credentials: boolean; sms: boolean }

const LEVELS = ["trace", "debug", "info", "warn", "error"];

export function loadConfig(path: string): Config {
  return parseConfig(readFileSync(path, "utf8"));
}

export function parseConfig(text: string): Config {
  const raw = parse(text);
  const server = table(raw, "server");
  const app = table(raw, "app");
  const policy = table(raw, "policy");
  const sockets = table(raw, "sockets");
  const store = table(raw, "store");
  const log = table(raw, "log");
  const firebase = table(raw, "firebase");
  const heartbeat = table(raw, "heartbeat");
  const modules = table(raw, "modules");
  const sms = table(raw, "sms");
  const config: Config = {
    server: { name: str(server, "server", "name", hostname()) },
    app: { host: str(app, "app", "host", "127.0.0.1"), port: int(app, "app", "port", 8770),
      publicUrl: str(app, "app", "public_url", ""), trustedProxies: strs(app, "app", "trusted_proxies") },
    policy: { requireUserAuth: bool(policy, "policy", "require_user_auth", true) },
    sockets: {
      broker: str(sockets, "sockets", "broker", "/run/vouch/broker.sock"),
      brokerGroup: str(sockets, "sockets", "broker_group", "vouch-broker"),
      admin: str(sockets, "sockets", "admin", "/run/vouch/admin.sock"),
      sms: str(sockets, "sockets", "sms", "/run/vouch/sms.sock"),
      smsGroup: str(sockets, "sockets", "sms_group", "vouch-sms"),
    },
    store: { path: str(store, "store", "path", "/var/lib/vouch/vouch.db") },
    log: { level: str(log, "log", "level", "info") },
    firebase: { serviceAccountFile: str(firebase, "firebase", "service_account_file", "") },
    heartbeat: { intervalHours: int(heartbeat, "heartbeat", "interval_hours", 24),
      silentAfterHours: int(heartbeat, "heartbeat", "silent_after_hours", 48) },
    modules: { credentials: bool(modules, "modules", "credentials", true), sms: bool(modules, "modules", "sms", false) },
    sms: {
      provider: str(sms, "sms", "provider", ""),
      ownerPhone: str(sms, "sms", "owner_phone", ""),
      dailyCap: int(sms, "sms", "daily_cap", 50),
      ownerDailyCap: int(sms, "sms", "owner_daily_cap", 30),
      intro: str(sms, "sms", "intro", ""),
      introMarker: str(sms, "sms", "intro_marker", ""),
      introGapDays: int(sms, "sms", "intro_gap_days", 7),
      maxText: int(sms, "sms", "max_text", 1000),
      voipms: { did: str(table(sms, "voipms"), "sms.voipms", "did", "") },
      ownerName: str(sms, "sms", "owner_name", "the owner"),
      agentName: str(sms, "sms", "agent_name", "the agent"),
      approvalTtlHours: int(sms, "sms", "approval_ttl_hours", 24),
      maxPendingApprovals: int(sms, "sms", "max_pending_approvals", 3),
      mqtt: {
        url: str(table(sms, "mqtt"), "sms.mqtt", "url", ""),
        topic: str(table(sms, "mqtt"), "sms.mqtt", "topic", "vouch/sms/inbound"),
        clientId: str(table(sms, "mqtt"), "sms.mqtt", "client_id", "vouch-sms"),
        agentInbox: str(table(sms, "mqtt"), "sms.mqtt", "agent_inbox", ""),
        sender: str(table(sms, "mqtt"), "sms.mqtt", "sender", "sms"),
      },
    },
  };
  if (config.modules.sms) {
    if (!config.sms.provider) throw new Error("sms.provider is required when modules.sms is on");
    if (!/^\+1[2-9][0-9]{9}$/.test(config.sms.ownerPhone)) {
      throw new Error("sms.owner_phone must be an E.164 Canadian or US number, like +12045550150");
    }
  }
  if (config.sms.dailyCap < 0 || config.sms.ownerDailyCap < 0 || config.sms.introGapDays < 0) {
    throw new Error("sms caps and intro_gap_days must not be negative");
  }
  if (config.sms.maxText < 1) throw new Error("sms.max_text must be at least 1");
  if (config.app.port < 0 || config.app.port > 65535) throw new Error("app.port must be 0 to 65535");
  // sun_path is 108 bytes on Linux, including the terminating NUL.
  for (const [key, path] of [["sockets.broker", config.sockets.broker], ["sockets.admin", config.sockets.admin],
    ["sockets.sms", config.sockets.sms]]) {
    if (Buffer.byteLength(path!) > 107) throw new Error(`${key} is longer than the 107 bytes a socket path allows`);
  }
  if (config.app.publicUrl && !/^https?:\/\/[^/]+$/.test(config.app.publicUrl)) {
    throw new Error("app.public_url must be a scheme and host, like https://vouch.example.com");
  }
  if (plainHttp(config.app.publicUrl) && !allowsPlainHttp(new URL(config.app.publicUrl).hostname)) {
    throw new Error("app.public_url must be https unless the host is this machine or on the local network " +
      "(a private address or a .local name): over plain http anyone on the path can read and change what the phone sees");
  }
  if (config.heartbeat.intervalHours < 1 || config.heartbeat.silentAfterHours <= config.heartbeat.intervalHours) {
    throw new Error("heartbeat.silent_after_hours must be longer than heartbeat.interval_hours (at least 1)");
  }
  if (!LEVELS.includes(config.log.level)) throw new Error(`log.level must be one of ${LEVELS.join(", ")}`);
  return config;
}

type Table = Record<string, unknown>;

function table(raw: Table, name: string): Table {
  const t = raw[name] ?? {};
  if (typeof t !== "object" || Array.isArray(t)) throw new Error(`[${name}] must be a table`);
  return t as Table;
}

function str(t: Table, section: string, key: string, fallback: string): string {
  const v = t[key] ?? fallback;
  if (typeof v !== "string") throw new Error(`${section}.${key} must be a string`);
  return v;
}

function int(t: Table, section: string, key: string, fallback: number): number {
  const v = t[key] ?? fallback;
  if (typeof v !== "number" || !Number.isInteger(v)) throw new Error(`${section}.${key} must be an integer`);
  return v;
}

function bool(t: Table, section: string, key: string, fallback: boolean): boolean {
  const v = t[key] ?? fallback;
  if (typeof v !== "boolean") throw new Error(`${section}.${key} must be true or false`);
  return v;
}

function strs(t: Table, section: string, key: string): string[] {
  const v = t[key] ?? [];
  if (!Array.isArray(v) || !v.every((x) => typeof x === "string")) throw new Error(`${section}.${key} must be a list of strings`);
  return v as string[];
}

export const plainHttp = (publicUrl: string): boolean => publicUrl.startsWith("http://");

// The same rule the app applies before pairing over plain http: this machine,
// a private or link-local address, or a .local name.
export function allowsPlainHttp(hostname: string): boolean {
  const h = hostname.toLowerCase().replace(/^\[|\]$/g, "");
  if (h === "localhost" || h.endsWith(".local")) return true;
  if (isIPv4(h)) {
    const [a, b] = h.split(".").map(Number) as [number, number];
    return a === 127 || a === 10 || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168) || (a === 169 && b === 254);
  }
  if (isIPv6(h)) return h === "::1" || /^f[cd]/.test(h) || /^fe[89ab]/.test(h);
  return false;
}
