import { parseArgs } from "node:util";
import { Alerts } from "./alerts.ts";
import { Approvals } from "./approvals.ts";
import { GOOGLE_ROOTS, rootKeys } from "./attestation.ts";
import { loadConfig, plainHttp } from "./config.ts";
import { openDb } from "./db.ts";
import { Devices } from "./devices.ts";
import { Fcm, loadServiceAccount } from "./fcm.ts";
import { Heartbeat } from "./heartbeat.ts";
import { createLogger } from "./log.ts";
import { Push } from "./push.ts";
import { start } from "./server.ts";
import { ContactApprovals } from "./sms/contact-approvals.ts";
import { Inbound } from "./sms/inbound.ts";
import { SmsUpdates } from "./sms/notify.ts";
import { SmsMqtt } from "./sms/mqtt.ts";
import { createProvider } from "./sms/providers.ts";
import { Sender } from "./sms/sender.ts";
import { startSmsSocket } from "./sms/socket.ts";
import { SmsStore } from "./sms/store.ts";
import type { Server } from "node:net";

process.umask(0o077);
const { values } = parseArgs({ options: { config: { type: "string", default: "/etc/vouch/config.toml" } } });
const config = loadConfig(values.config);
const log = createLogger(config.log.level);
const db = openDb(config.store.path);
const approvals = new Approvals(db, log);
approvals.start();
const devices = new Devices(db, log);
const fcm = config.firebase.serviceAccountFile ? new Fcm(loadServiceAccount(config.firebase.serviceAccountFile)) : null;
if (!fcm) log.warn({}, "push_disabled_no_service_account");
if (plainHttp(config.app.publicUrl)) log.warn({ public_url: config.app.publicUrl }, "public_url_not_encrypted");
const push = new Push(fcm, devices, log, (id, at) => approvals.markPushSent(id, at));
let contactApprovals: ContactApprovals | null = null;
approvals.hooks = {
  created: (a) => void push.request(a).catch((err) => log.error({ request_id: a.request_id, err }, "push_failed")),
  settled: (a) => {
    void push.clear(a).catch((err) => log.error({ request_id: a.request_id, err }, "push_failed"));
    contactApprovals?.settled(a);
  },
};
devices.purge();
setInterval(() => devices.purge(), 3600 * 1000).unref();
const alerts = new Alerts(db, log);
alerts.created = (a) => void push.alert(a.alert_id).catch((err) => log.error({ alert_id: a.alert_id, err }, "push_failed"));
alerts.purge();
setInterval(() => alerts.purge(), 3600 * 1000).unref();
const heartbeat = new Heartbeat(db, push, log, config.heartbeat);
// The heartbeat is a push that phones answer. Without push nothing would answer,
// and every phone would be reported silent.
if (fcm) heartbeat.start();
const service = await start(config, { log, db, approvals, devices, heartbeat, alerts, roots: rootKeys(GOOGLE_ROOTS) });

let smsMqtt: SmsMqtt | null = null;
let smsSocket: Server | null = null;
if (config.modules.sms) {
  const provider = createProvider(config.sms);
  const store = new SmsStore(db);
  const owner = { phone: config.sms.ownerPhone, name: config.sms.ownerName };
  const updates = new SmsUpdates(() => push.smsUpdated(), log);
  const sender = new Sender(provider, store, config.sms, log, () => new Date(), () => updates.stored());
  if (config.sms.mqtt.url) {
    // The relay needs the connection and the connection needs the handler, so the handler reaches it late.
    const inbound = new Inbound(provider, store, owner, (text) => smsMqtt?.relay(text), log, () => updates.stored());
    smsMqtt = new SmsMqtt(config.sms.mqtt, process.env, (body) => inbound.handle(body), log);
  }
  contactApprovals = new ContactApprovals(approvals, store, { ownerPhone: owner.phone, ownerName: owner.name,
    agentName: config.sms.agentName, ttlHours: config.sms.approvalTtlHours, maxPending: config.sms.maxPendingApprovals },
  (text) => smsMqtt?.relay(text), log);
  const contacts = contactApprovals;
  const day = () => new Date(Date.now() - 24 * 3600 * 1000).toISOString();
  smsSocket = await startSmsSocket(config.sockets.sms, config.sockets.smsGroup || null, { sender, store, owner, log,
    requestApproval: (phone, name, reason) => contacts.request(phone, name, reason),
    pendingApprovals: () => contacts.pending(),
    status: () => ({ provider: provider.name, listener: smsMqtt?.connected ?? false,
      sent_last_24h: store.sentSince(day(), { except: owner.phone }), daily_cap: config.sms.dailyCap,
      owner_sent_last_24h: store.sentSince(day(), { only: owner.phone }), owner_daily_cap: config.sms.ownerDailyCap }) });
}

for (const signal of ["SIGTERM", "SIGINT"] as const) {
  process.once(signal, async () => {
    log.info({ signal }, "stopping");
    approvals.stop();
    heartbeat.stop();
    await service.close();
    await smsMqtt?.close();
    smsSocket?.close();
    db.close();
    process.exit(0);
  });
}
