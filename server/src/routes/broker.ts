import type { FastifyInstance } from "fastify";
import type { Alerts, NewAlert } from "../alerts.ts";
import type { Approval, Approvals } from "../approvals.ts";
import { isHost, lines, oneLine } from "../text.ts";

const MAX_WAIT_S = 30;
const MAX_TTL_MS = 3600 * 1000;

interface CreateBody {
  request_id: string;
  kind: "sign_in";
  agent: string;
  site: string;
  login_title?: string | null;
  expires_at: string;
}

const status = (a: Approval) => ({
  request_id: a.request_id,
  state: a.state,
  device_id: a.device_id,
  decided_at: a.decided_at,
  push_sent_at: a.push_sent_at,
  fetched_at: a.fetched_at,
});

const bad = (message: string) => ({ code: "bad_request", message });
const PLAIN = "must be one line of visible text, with no control or invisible characters.";

const notFound = { code: "not_found", message: "No approval with that id." };

// The broker's side of an approval: create it, wait for the answer, or give up.
export function brokerRoutes(app: FastifyInstance, approvals: Approvals, alerts: Alerts): void {
  app.post<{ Body: CreateBody }>("/v1/approvals", {
    schema: {
      body: {
        type: "object",
        additionalProperties: false,
        required: ["request_id", "kind", "agent", "site", "expires_at"],
        properties: {
          request_id: { type: "string", pattern: "^[A-Za-z0-9_-]{8,64}$" },
          kind: { type: "string", enum: ["sign_in"] },
          agent: { type: "string", minLength: 1, maxLength: 64 },
          site: { type: "string", minLength: 1, maxLength: 253 },
          login_title: { type: ["string", "null"], maxLength: 200 },
          expires_at: { type: "string", format: "date-time" },
        },
      },
    },
  }, async (req, reply) => {
    const b = req.body;
    if (!oneLine(b.agent)) return reply.code(400).send(bad(`agent ${PLAIN}`));
    if (!isHost(b.site)) return reply.code(400).send(bad("site must be a host name or an IP address, such as example.com."));
    if (b.login_title != null && !oneLine(b.login_title)) return reply.code(400).send(bad(`login_title ${PLAIN}`));
    const expires = Date.parse(b.expires_at);
    if (!(expires > Date.now() && expires <= Date.now() + MAX_TTL_MS)) {
      return reply.code(400).send({ code: "bad_request", message: "expires_at must be in the next hour." });
    }
    // Host names ignore case, and a capital I reads as a small l on the phone.
    const r = approvals.create({ request_id: b.request_id, kind: b.kind, agent: b.agent, site: b.site.toLowerCase(),
      login_title: b.login_title ?? null, expires_at: new Date(expires).toISOString() });
    if ("conflict" in r) {
      return reply.code(409).send({ code: "bad_request", message: "That request_id is already used by a different request." });
    }
    return reply.code(202).send(status(r.approval));
  });

  app.get<{ Params: { id: string }; Querystring: { wait?: number } }>("/v1/approvals/:id", {
    schema: {
      querystring: {
        type: "object",
        additionalProperties: false,
        properties: { wait: { type: "integer", minimum: 0, maximum: MAX_WAIT_S } },
      },
    },
  }, async (req, reply) => {
    const a = await approvals.wait(req.params.id, req.query.wait ?? 0);
    return a ? status(a) : reply.code(404).send(notFound);
  });

  app.post<{ Params: { id: string } }>("/v1/approvals/:id/cancel", async (req, reply) => {
    const a = approvals.cancel(req.params.id);
    if (!a) return reply.code(404).send(notFound);
    if (a.state !== "cancelled") {
      return reply.code(409).send({ code: "already_decided", message: `The approval is already ${a.state}.`, ...status(a) });
    }
    return reply.code(204).send();
  });

  // Tell the owner's phones about a problem. The push carries only the id.
  app.post<{ Body: NewAlert }>("/v1/alerts", {
    schema: {
      body: {
        type: "object",
        additionalProperties: false,
        required: ["alert_id", "severity", "title", "body"],
        properties: {
          alert_id: { type: "string", pattern: "^[A-Za-z0-9_-]{8,64}$" },
          severity: { type: "string", enum: ["info", "warning", "critical"] },
          title: { type: "string", minLength: 1, maxLength: 120 },
          body: { type: "string", minLength: 1, maxLength: 2000 },
        },
      },
    },
  }, async (req, reply) => {
    if (!oneLine(req.body.title)) return reply.code(400).send(bad(`title ${PLAIN}`));
    if (!lines(req.body.body)) {
      return reply.code(400).send(bad("body must be visible text. Line breaks are allowed; other control or invisible characters are not."));
    }
    const r = alerts.create(req.body);
    if ("refused" in r) {
      return r.refused === "conflict"
        ? reply.code(409).send({ code: "bad_request", message: "That alert_id is already used by a different alert." })
        : reply.code(429).send({ code: "rate_limited", message: "Too many alerts in the last hour." });
    }
    return reply.code(202).send({ alert_id: r.alert.alert_id, created_at: r.alert.created_at });
  });
}
