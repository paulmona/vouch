import { chmodSync, chownSync, existsSync, readFileSync, unlinkSync } from "node:fs";
import { connect } from "node:net";
import type { DatabaseSync } from "node:sqlite";
import Fastify, { LogController, type FastifyBaseLogger, type FastifyInstance } from "fastify";
import { Alerts } from "./alerts.ts";
import type { Approvals } from "./approvals.ts";
import type { Devices } from "./devices.ts";
import type { Heartbeat } from "./heartbeat.ts";
import type { Config } from "./config.ts";
import type { Logger } from "./log.ts";
import { adminRoutes } from "./routes/admin.ts";
import { appRoutes } from "./routes/app.ts";
import { brokerRoutes } from "./routes/broker.ts";
import { smsRoutes } from "./routes/sms.ts";
import { SmsStore } from "./sms/store.ts";

export type ListenerName = "app" | "broker" | "admin";

export interface Deps {
  log: Logger;
  db: DatabaseSync;
  approvals: Approvals;
  devices: Devices;
  roots: Buffer[];
  heartbeat?: Heartbeat;
  alerts?: Alerts;
}

const VERSION: string = JSON.parse(readFileSync(new URL("../package.json", import.meta.url), "utf8")).version;

export function buildListener(name: ListenerName, { log, db }: Deps, trustedProxies: string[] = []): FastifyInstance {
  const logger: FastifyBaseLogger = log.child({ listener: name });
  const app = Fastify({
    loggerInstance: logger,
    logController: new LogController({ disableRequestLogging: true }),
    // Unknown fields are refused rather than silently dropped.
    ajv: { customOptions: { removeAdditional: false } },
    // Behind cloudflared, the client address comes from X-Forwarded-For, but
    // only when the connection is from a proxy named in the config.
    ...(trustedProxies.length ? { trustProxy: trustedProxies } : {}),
    // The app API is reachable from the internet through the tunnel; its bodies are tiny.
    bodyLimit: name === "app" ? 64 * 1024 : 1024 * 1024,
  });
  app.addHook("onResponse", async (req, reply) => {
    log.info({ listener: name, method: req.method, route: req.routeOptions.url ?? "unmatched",
      status: reply.statusCode, latency_ms: Math.round(reply.elapsedTime) }, "http");
  });
  app.setErrorHandler((err: { validation?: unknown; statusCode?: number; message: string }, req, reply) => {
    if (err.validation) return reply.code(400).send({ code: "bad_request", message: err.message });
    if (err.statusCode && err.statusCode < 500) return reply.code(err.statusCode).send({ code: "bad_request", message: err.message });
    log.error({ listener: name, route: req.routeOptions.url, err }, "unhandled_error");
    return reply.code(500).send({ code: "internal", message: "Something went wrong." });
  });
  app.get("/healthz", { config: { signedBy: "none" } }, async () => {
    db.prepare("SELECT 1").get();
    return { ok: true, service: "approver", listener: name, version: VERSION };
  });
  return app;
}

export interface Service {
  listeners: Record<ListenerName, FastifyInstance>;
  appAddress: { host: string; port: number };
  close(): Promise<void>;
}

// Who may call a socket is decided by the kernel through file permissions: the
// broker socket is 0660 with the configured group (the broker's user is its only
// other member), the admin socket 0600. Node has no SO_PEERCRED, and a refused
// connect() is a stronger answer than checking a uid after accepting.
export async function start(config: Config, deps: Deps): Promise<Service> {
  const listeners = {
    app: buildListener("app", deps, config.app.trustedProxies),
    broker: buildListener("broker", deps),
    admin: buildListener("admin", deps),
  };
  const alerts = deps.alerts ?? new Alerts(deps.db, deps.log);
  if (config.modules.credentials) {
    brokerRoutes(listeners.broker, deps.approvals, alerts);
  } else {
    listeners.broker.all("/v1/*", async (_req, reply) =>
      reply.code(403).send({ code: "module_disabled", message: "The credentials module is off on this server." }));
  }
  adminRoutes(listeners.admin, { config, devices: deps.devices });
  appRoutes(listeners.app, { config, approvals: deps.approvals, devices: deps.devices, heartbeat: deps.heartbeat,
    alerts, log: deps.log, roots: deps.roots });
  if (config.modules.sms) smsRoutes(listeners.app, { config, store: new SmsStore(deps.db), log: deps.log });
  const opened: FastifyInstance[] = [];
  const close = async () => {
    await Promise.all(opened.map((l) => l.close()));
  };
  try {
    await listenSocket(listeners.broker, config.sockets.broker, config.sockets.brokerGroup || null);
    opened.push(listeners.broker);
    await listenSocket(listeners.admin, config.sockets.admin, null);
    opened.push(listeners.admin);
    await listeners.app.listen({ host: config.app.host, port: config.app.port });
    opened.push(listeners.app);
  } catch (e) {
    await close();
    throw e;
  }
  const addr = listeners.app.server.address();
  const appAddress = typeof addr === "object" && addr ? { host: addr.address, port: addr.port } : config.app;
  deps.log.info({ app: appAddress, broker: config.sockets.broker, admin: config.sockets.admin, version: VERSION }, "started");
  return { listeners, appAddress, close };
}

async function listenSocket(app: FastifyInstance, path: string, group: string | null): Promise<void> {
  await clearStale(path);
  // The process umask (0077, set in main) means the socket is born owner-only, so
  // there is no window in which it is wider than intended.
  await app.listen({ path });
  if (group) {
    chownSync(path, -1, gidOf(group));
    chmodSync(path, 0o660);
  } else {
    chmodSync(path, 0o600);
  }
}

export async function clearStale(path: string): Promise<void> {
  if (!existsSync(path)) return;
  const live = await new Promise<boolean>((resolve) => {
    const s = connect(path)
      .once("connect", () => { s.destroy(); resolve(true); })
      .once("error", () => resolve(false));
  });
  if (live) throw new Error(`${path} is in use: is another approver running?`);
  unlinkSync(path);
}

export function gidOf(group: string, groupFile = "/etc/group"): number {
  if (/^\d+$/.test(group)) return Number(group);
  for (const line of readFileSync(groupFile, "utf8").split("\n")) {
    const [name, , gid] = line.split(":");
    if (name === group && gid) return Number(gid);
  }
  throw new Error(`group ${group} does not exist`);
}
