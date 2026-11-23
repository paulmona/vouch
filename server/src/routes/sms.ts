import type { FastifyInstance } from "fastify";
import type { Config } from "../config.ts";
import type { Logger } from "../log.ts";
import { BadNumber, normalize } from "../sms/phone.ts";
import type { SmsContactRow, SmsMessageRow, SmsStore } from "../sms/store.ts";

const PHONE = "^\\+[1-9][0-9]{6,14}$";
const ID = "^[A-Za-z0-9_-]{8,64}$";
const phoneParam = { type: "object", required: ["phone"], properties: { phone: { type: "string", pattern: PHONE } } };

const messageView = (m: SmsMessageRow) =>
  ({ message_id: m.message_id, phone: m.phone, direction: m.direction, text: m.text, at: m.at, status: m.status });
const contactView = (c: SmsContactRow) => ({ phone: c.phone, name: c.name, added_at: c.added_at, added_by: c.added_by });

// The app's SMS endpoints. Only registered when modules.sms is on, so with
// it off every /v1/sms path is a 404. Signatures cover the raw URL as sent, so a
// %2B-encoded and a literal + number both verify; the path parameter arrives
// percent-decoded, and + is never read as a space.
// Logs carry counts and outcomes, never message text or full numbers.
export function smsRoutes(app: FastifyInstance, { config, store, log, now = () => new Date() }:
  { config: Config; store: SmsStore; log: Logger; now?: () => Date }): void {
  const userAuthMissing = (bound: string) => config.policy.requireUserAuth && bound === "none";
  const policyRefusal = { code: "policy_requires_user_auth",
    message: "This phone's key does not need a fingerprint or PIN, which this server requires. Pair it again." };

  app.get("/v1/sms/conversations", async () => ({
    conversations: store.conversations().map((c) => ({ phone: c.phone, contact_name: c.contact_name,
      last_message: messageView(c), unread_count: c.unread })),
  }));

  app.get<{ Params: { phone: string }; Querystring: { before?: string; limit?: number } }>(
    "/v1/sms/conversations/:phone/messages", {
      schema: { params: phoneParam, querystring: { type: "object", additionalProperties: false,
        properties: { before: { type: "string", pattern: ID }, limit: { type: "integer", minimum: 1, maximum: 100 } } } },
    }, async (req, reply) => {
      const page = store.page(req.params.phone, req.query.limit ?? 50, req.query.before);
      if (!page) return reply.code(400).send({ code: "bad_request", message: "That page cursor is not in this conversation." });
      if (!req.query.before) store.markRead(req.params.phone, now().toISOString());
      return { messages: page.messages.map(messageView), next_before: page.nextBefore };
    });

  app.delete<{ Params: { phone: string } }>("/v1/sms/conversations/:phone", { schema: { params: phoneParam } },
    async (req, reply) => {
      const n = store.deleteConversation(req.params.phone);
      log.info({ device_id: req.device!.device_id, deleted: n }, "sms_conversation_deleted");
      return reply.code(204).send();
    });

  app.post<{ Body: { message_ids: string[] } }>("/v1/sms/messages/delete", {
    schema: { body: { type: "object", additionalProperties: false, required: ["message_ids"], properties: {
      message_ids: { type: "array", minItems: 1, maxItems: 200, uniqueItems: true, items: { type: "string", pattern: ID } } } } },
  }, async (req) => {
    const deleted = store.deleteMessages(req.body.message_ids);
    log.info({ device_id: req.device!.device_id, deleted }, "sms_messages_deleted");
    return { deleted };
  });

  app.get("/v1/sms/contacts", async () => ({ contacts: store.contacts().map(contactView) }));

  app.post<{ Body: { phone: string; name: string } }>("/v1/sms/contacts", {
    config: { signedBy: "decision" },
    schema: { body: { type: "object", additionalProperties: false, required: ["phone", "name"], properties: {
      phone: { type: "string", minLength: 3, maxLength: 32 }, name: { type: "string", minLength: 1, maxLength: 64 } } } },
  }, async (req, reply) => {
    const device = req.device!;
    if (userAuthMissing(device.user_auth_bound)) return reply.code(422).send(policyRefusal);
    let phone: string;
    try {
      phone = normalize(req.body.phone);
    } catch (e) {
      if (e instanceof BadNumber) return reply.code(422).send({ code: "invalid_number", message: e.message });
      throw e;
    }
    const name = req.body.name.trim();
    if (!name) return reply.code(400).send({ code: "bad_request", message: "The contact needs a name." });
    const row = { phone, name, added_at: now().toISOString(), added_by: "owner" as const, device_id: device.device_id };
    if (!store.addContact(row)) {
      return reply.code(409).send({ code: "contact_exists", message: `${name}'s number is already permitted.` });
    }
    log.info({ device_id: device.device_id, phone_last4: phone.slice(-4), outcome: "added" }, "sms_contact");
    return reply.code(201).send(contactView({ ...row, request_id: null }));
  });

  app.delete<{ Params: { phone: string } }>("/v1/sms/contacts/:phone", {
    config: { signedBy: "decision" }, schema: { params: phoneParam },
  }, async (req, reply) => {
    const device = req.device!;
    if (userAuthMissing(device.user_auth_bound)) return reply.code(422).send(policyRefusal);
    if (!store.removeContact(req.params.phone, now().toISOString(), device.device_id)) {
      return reply.code(404).send({ code: "not_found", message: "That number is not a permitted contact." });
    }
    log.info({ device_id: device.device_id, phone_last4: req.params.phone.slice(-4), outcome: "removed" }, "sms_contact");
    return reply.code(204).send();
  });
}
