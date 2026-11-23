import { chmodSync, chownSync } from "node:fs";
import { createServer, type Server, type Socket } from "node:net";
import type { Logger } from "../log.ts";
import { clearStale, gidOf } from "../server.ts";
import { BadNumber, normalize } from "./phone.ts";
import { Refused, type Sender } from "./sender.ts";
import type { SmsStore } from "./store.ts";

// The agents' SMS socket: newline-delimited JSON, one request per line,
// one reply per request. Who may connect is the
// kernel's call through file permissions (0660, group vouch-sms); Node has no
// SO_PEERCRED, the same reason the broker socket works this way.
//
//   {"id": 1, "op": "send", "to": "...", "text": "..."}
//   {"id": 1, "ok": true, "result": {...}}  or  {"id": 1, "ok": false, "error": {"code": "...", "message": "..."}}

export interface SmsSocketDeps {
  sender: Sender;
  store: SmsStore;
  owner: { phone: string; name: string };
  status: () => Record<string, unknown>;
  requestApproval?: (phone: string, name: string, reason: string) => Promise<Record<string, unknown>>;
  pendingApprovals?: () => object[];
  log: Logger;
}

const MAX_LINE = 16 * 1024;

class BadRequest extends Error {}

const str = (req: Record<string, unknown>, key: string, optional = false): string => {
  const v = req[key];
  if (v === undefined && optional) return "";
  if (typeof v !== "string") throw new BadRequest(`${key} must be a string`);
  return v;
};

export async function handleOp(req: Record<string, unknown>, d: SmsSocketDeps): Promise<Record<string, unknown>> {
  switch (req.op) {
    case "send": {
      const r = await d.sender.send(str(req, "to"), str(req, "text"));
      return { sent: true, to: r.to, text: r.text, message_id: r.messageId };
    }
    case "request_approval": {
      if (!d.requestApproval) throw new Refused("not_available", "Contact approval through Vouch isn't available yet.");
      let phone: string;
      try {
        phone = normalize(str(req, "phone"));
      } catch (e) {
        if (e instanceof BadNumber) throw new Refused("invalid", e.message);
        throw e;
      }
      return d.requestApproval(phone, str(req, "name"), str(req, "reason"));
    }
    case "contacts":
      return { owner: d.owner, contacts: d.store.contacts().map((c) => ({ phone: c.phone, name: c.name, added_at: c.added_at })),
        pending: d.pendingApprovals?.() ?? [] };
    case "history": {
      const raw = str(req, "phone", true);
      let phone: string | null = null;
      if (raw) {
        try {
          phone = normalize(raw);
        } catch (e) {
          if (e instanceof BadNumber) throw new Refused("invalid", e.message);
          throw e;
        }
      }
      const limit = typeof req.limit === "number" && Number.isInteger(req.limit) ? Math.max(1, Math.min(req.limit, 200)) : 20;
      return { messages: d.store.history(phone, limit).map((m) =>
        ({ at: m.at, direction: m.direction, phone: m.phone, text: m.text, status: m.status })) };
    }
    case "status":
      return d.status();
    default:
      throw new BadRequest(`unknown op ${JSON.stringify(req.op)}`);
  }
}

export async function startSmsSocket(path: string, group: string | null, d: SmsSocketDeps): Promise<Server> {
  await clearStale(path);
  const server = createServer((sock) => serve(sock, d));
  await new Promise<void>((resolve, reject) => server.once("error", reject).listen(path, () => resolve()));
  if (group) {
    chownSync(path, -1, gidOf(group));
    chmodSync(path, 0o660);
  } else {
    chmodSync(path, 0o600);
  }
  d.log.info({ socket: path }, "sms_socket_listening");
  return server;
}

function serve(sock: Socket, d: SmsSocketDeps): void {
  let buf = "";
  let chain = Promise.resolve();
  sock.setEncoding("utf8");
  sock.on("data", (chunk: string) => {
    buf += chunk;
    if (buf.length > MAX_LINE && !buf.includes("\n")) {
      sock.end(`${JSON.stringify({ id: null, ok: false, error: { code: "bad_request", message: "line too long" } })}\n`);
      return;
    }
    let nl: number;
    while ((nl = buf.indexOf("\n")) >= 0) {
      const line = buf.slice(0, nl).trim();
      buf = buf.slice(nl + 1);
      if (!line) continue;
      // One at a time per connection, so replies come back in order.
      chain = chain.then(() => reply(line, d)).then((out) => { if (!sock.destroyed) sock.write(`${out}\n`); });
    }
  });
  sock.on("error", () => sock.destroy());
}

async function reply(line: string, d: SmsSocketDeps): Promise<string> {
  let req: Record<string, unknown>;
  try {
    const parsed: unknown = JSON.parse(line);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error();
    req = parsed as Record<string, unknown>;
  } catch {
    return JSON.stringify({ id: null, ok: false, error: { code: "bad_request", message: "each line must be a JSON object" } });
  }
  const id = req.id ?? null;
  try {
    const result = await handleOp(req, d);
    d.log.info({ op: req.op, outcome: "ok" }, "sms_socket");
    return JSON.stringify({ id, ok: true, result });
  } catch (e) {
    if (e instanceof Refused) {
      d.log.info({ op: req.op, outcome: e.code }, "sms_socket");
      return JSON.stringify({ id, ok: false, error: { code: e.code, message: e.message } });
    }
    if (e instanceof BadRequest) return JSON.stringify({ id, ok: false, error: { code: "bad_request", message: e.message } });
    d.log.error({ op: req.op, err: (e as Error).message }, "sms_socket_error");
    return JSON.stringify({ id, ok: false, error: { code: "internal", message: "Something went wrong." } });
  }
}
