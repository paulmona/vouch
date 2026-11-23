import { randomBytes } from "node:crypto";
import type { DatabaseSync } from "node:sqlite";

export type Direction = "inbound" | "outbound";
export type MessageStatus = "received" | "sent" | "failed";

export interface SmsMessageRow {
  message_id: string;
  phone: string;
  direction: Direction;
  text: string;
  at: string;
  status: MessageStatus;
  provider: string;
  provider_id: string | null;
  read_at: string | null;
}

export interface SmsContactRow {
  phone: string;
  name: string;
  added_at: string;
  added_by: "owner" | "agent_request" | "import";
  device_id: string | null;
  request_id: string | null;
}

export class SmsStore {
  readonly #db: DatabaseSync;

  constructor(db: DatabaseSync) {
    this.#db = db;
  }

  // Returns null when (provider, provider_id) is already stored: a duplicate delivery.
  record(m: Omit<SmsMessageRow, "message_id" | "read_at">): string | null {
    const id = `msg_${randomBytes(12).toString("base64url")}`;
    const r = this.#db.prepare(`INSERT INTO sms_messages (message_id, phone, direction, text, at, status, provider, provider_id)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT (provider, provider_id) DO NOTHING`)
      .run(id, m.phone, m.direction, m.text, m.at, m.status, m.provider, m.provider_id);
    return r.changes ? id : null;
  }

  contactName(phone: string): string | null {
    const r = this.#db.prepare("SELECT name FROM sms_contacts WHERE phone = ?").get(phone) as { name: string } | undefined;
    return r?.name ?? null;
  }

  sentSince(since: string, to: { only: string } | { except: string }): number {
    const [op, phone] = "only" in to ? ["=", to.only] : ["!=", to.except];
    return (this.#db.prepare(`SELECT count(*) AS n FROM sms_messages
      WHERE direction = 'outbound' AND status = 'sent' AND at >= ? AND phone ${op} ?`).get(since, phone) as { n: number }).n;
  }

  conversations(): (SmsMessageRow & { contact_name: string | null; unread: number })[] {
    return this.#db.prepare(`SELECT m.*, c.name AS contact_name,
        (SELECT count(*) FROM sms_messages u WHERE u.phone = m.phone AND u.direction = 'inbound' AND u.read_at IS NULL) AS unread
      FROM sms_messages m LEFT JOIN sms_contacts c ON c.phone = m.phone
      WHERE m.message_id = (SELECT x.message_id FROM sms_messages x WHERE x.phone = m.phone
                            ORDER BY x.at DESC, x.message_id DESC LIMIT 1)
      ORDER BY m.at DESC, m.message_id DESC`).all() as unknown as (SmsMessageRow & { contact_name: string | null; unread: number })[];
  }

  // Newest first. `before` is a message id from the previous page; undefined when
  // that message isn't in this conversation.
  page(phone: string, limit: number, before?: string): { messages: SmsMessageRow[]; nextBefore: string | null } | undefined {
    let rows: SmsMessageRow[];
    if (before) {
      const cursor = this.#db.prepare("SELECT at, message_id FROM sms_messages WHERE message_id = ? AND phone = ?")
        .get(before, phone) as { at: string; message_id: string } | undefined;
      if (!cursor) return undefined;
      rows = this.#db.prepare(`SELECT * FROM sms_messages WHERE phone = ? AND (at < ? OR (at = ? AND message_id < ?))
        ORDER BY at DESC, message_id DESC LIMIT ?`).all(phone, cursor.at, cursor.at, cursor.message_id, limit + 1) as unknown as SmsMessageRow[];
    } else {
      rows = this.#db.prepare("SELECT * FROM sms_messages WHERE phone = ? ORDER BY at DESC, message_id DESC LIMIT ?")
        .all(phone, limit + 1) as unknown as SmsMessageRow[];
    }
    const more = rows.length > limit;
    const messages = rows.slice(0, limit);
    return { messages, nextBefore: more ? messages.at(-1)!.message_id : null };
  }

  markRead(phone: string, at: string): void {
    this.#db.prepare("UPDATE sms_messages SET read_at = ? WHERE phone = ? AND direction = 'inbound' AND read_at IS NULL")
      .run(at, phone);
  }

  deleteConversation(phone: string): number {
    return Number(this.#db.prepare("DELETE FROM sms_messages WHERE phone = ?").run(phone).changes);
  }

  deleteMessages(ids: string[]): number {
    const del = this.#db.prepare("DELETE FROM sms_messages WHERE message_id = ?");
    let n = 0;
    this.#db.exec("BEGIN");
    try {
      for (const id of ids) n += Number(del.run(id).changes);
      this.#db.exec("COMMIT");
    } catch (e) {
      this.#db.exec("ROLLBACK");
      throw e;
    }
    return n;
  }

  contacts(): SmsContactRow[] {
    return this.#db.prepare("SELECT * FROM sms_contacts ORDER BY name COLLATE NOCASE, phone").all() as unknown as SmsContactRow[];
  }

  // False when the number is already permitted.
  addContact(c: Omit<SmsContactRow, "request_id"> & { request_id?: string | null }): boolean {
    this.#db.exec("BEGIN");
    try {
      const r = this.#db.prepare(`INSERT INTO sms_contacts (phone, name, added_at, added_by, device_id, request_id)
        VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT (phone) DO NOTHING`)
        .run(c.phone, c.name, c.added_at, c.added_by, c.device_id, c.request_id ?? null);
      if (r.changes) {
        this.#db.prepare(`INSERT INTO sms_contact_events (phone, action, at, added_by, device_id, request_id)
          VALUES (?, 'add', ?, ?, ?, ?)`).run(c.phone, c.added_at, c.added_by, c.device_id, c.request_id ?? null);
      }
      this.#db.exec("COMMIT");
      return r.changes > 0;
    } catch (e) {
      this.#db.exec("ROLLBACK");
      throw e;
    }
  }

  // False when the number wasn't permitted.
  removeContact(phone: string, at: string, deviceId: string): boolean {
    this.#db.exec("BEGIN");
    try {
      const r = this.#db.prepare("DELETE FROM sms_contacts WHERE phone = ?").run(phone);
      if (r.changes) {
        this.#db.prepare("INSERT INTO sms_contact_events (phone, action, at, device_id) VALUES (?, 'remove', ?, ?)")
          .run(phone, at, deviceId);
      }
      this.#db.exec("COMMIT");
      return r.changes > 0;
    } catch (e) {
      this.#db.exec("ROLLBACK");
      throw e;
    }
  }

  // Oldest first.
  history(phone: string | null, limit: number): SmsMessageRow[] {
    const rows = (phone
      ? this.#db.prepare("SELECT * FROM sms_messages WHERE phone = ? ORDER BY at DESC, message_id DESC LIMIT ?").all(phone, limit)
      : this.#db.prepare("SELECT * FROM sms_messages ORDER BY at DESC, message_id DESC LIMIT ?").all(limit)) as unknown as SmsMessageRow[];
    return rows.reverse();
  }

  lastSentTo(phone: string): string | null {
    const r = this.#db.prepare(`SELECT max(at) AS at FROM sms_messages
      WHERE direction = 'outbound' AND status = 'sent' AND phone = ?`).get(phone) as { at: string | null };
    return r.at;
  }
}
