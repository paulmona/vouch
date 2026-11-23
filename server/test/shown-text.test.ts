// Text an agent supplies and the owner reads on the phone: nothing in it may hide, reorder or
// push aside what is shown.
import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { Alerts } from "../src/alerts.ts";
import { Approvals, type NewApproval } from "../src/approvals.ts";
import { openDb } from "../src/db.ts";
import { Devices } from "../src/devices.ts";
import { createLogger } from "../src/log.ts";
import { brokerRoutes } from "../src/routes/broker.ts";
import { buildListener } from "../src/server.ts";
import { ContactApprovals } from "../src/sms/contact-approvals.ts";
import { SmsStore } from "../src/sms/store.ts";

const log = createLogger("error");
const open: Approvals[] = [];
afterEach(() => { for (const a of open.splice(0)) a.stop(); });

function setup() {
  const db = openDb(":memory:");
  const approvals = new Approvals(db, log);
  open.push(approvals);
  approvals.start();
  const alerts = new Alerts(db, log);
  const app = buildListener("broker", { log, db, approvals, devices: new Devices(db, log), roots: [] });
  brokerRoutes(app, approvals, alerts);
  const post = (payload: object) => app.inject({ method: "POST", url: "/v1/approvals", payload });
  const alert = (payload: object) => app.inject({ method: "POST", url: "/v1/alerts", payload });
  return { db, approvals, alerts, app, post, alert };
}

let n = 0;
const req = (over: Partial<NewApproval> = {}): NewApproval =>
  ({ request_id: `req_text_${String(++n).padStart(4, "0")}`, kind: "sign_in", agent: "Research agent", site: "example.com",
    login_title: "Example", expires_at: new Date(Date.now() + 300_000).toISOString(), ...over });
const BIDI = "\u202e"; // RIGHT-TO-LEFT OVERRIDE

test("site: a newline is refused", async () => {
  const r = await setup().post(req({ site: "example.com\nApproved by owner" }));
  assert.equal(r.statusCode, 400, r.body);
});

test("site: values that are not hostnames are refused", async () => {
  const s = setup();
  for (const site of ["not a hostname!!", "https://example.com/path?x=1", "exa mple.com", "example.com/", " ", "a..b"]) {
    const r = await s.post(req({ site }));
    assert.equal(r.statusCode, 400, `site ${JSON.stringify(site)} -> ${r.statusCode}`);
  }
});

test("agent: a bidi override is refused", async () => {
  const r = await setup().post(req({ agent: `Research${BIDI}tnega` }));
  assert.equal(r.statusCode, 400, r.body);
});

test("agent: a single space is refused", async () => {
  const r = await setup().post(req({ agent: " " }));
  assert.equal(r.statusCode, 400, r.body);
});

test("login_title: newline and bidi override are refused", async () => {
  const s = setup();
  for (const login_title of ["Example\nline two", `Exa${BIDI}mple`, "\u0007bell"]) {
    const r = await s.post(req({ login_title }));
    assert.equal(r.statusCode, 400, `login_title ${JSON.stringify(login_title)} -> ${r.statusCode}`);
  }
});

test("NUL in site: refused, not stored truncated", async () => {
  const s = setup();
  const body = req({ site: "example.com\u0000.evil.example" });
  const r = await s.post(body);
  const stored = s.approvals.get(body.request_id);
  assert.equal(stored, undefined, `stored site reads back as ${JSON.stringify(stored?.site)}`);
  assert.equal(r.statusCode, 400, r.body);
});

test("NUL in agent and login_title: refused", async () => {
  const s = setup();
  assert.equal((await s.post(req({ agent: "Research\u0000agent" }))).statusCode, 400, "agent");
  assert.equal((await s.post(req({ login_title: "Exa\u0000mple" }))).statusCode, 400, "login_title");
});

const alertBody = (over: object = {}) =>
  ({ alert_id: `alert_text_${String(++n).padStart(4, "0")}`, severity: "info", title: "Password found", body: "details", ...over });

test("alert title: newline, bidi override and NUL are refused", async () => {
  const s = setup();
  for (const title of ["Line one\nLine two", `Pass${BIDI}word`, "nul\u0000here", " "]) {
    const r = await s.alert(alertBody({ title }));
    assert.equal(r.statusCode, 400, `title ${JSON.stringify(title)} -> ${r.statusCode}`);
  }
});

test("alert body: bidi override, NUL and other control characters are refused", async () => {
  const s = setup();
  for (const body of [`evil${BIDI}txet`, "nul\u0000here", "bell\u0007", " "]) {
    const r = await s.alert(alertBody({ body }));
    assert.equal(r.statusCode, 400, `body ${JSON.stringify(body)} -> ${r.statusCode}`);
  }
});

test("sms contact name and reason: newline, bidi override and NUL are refused", async () => {
  const db = openDb(":memory:");
  const approvals = new Approvals(db, log);
  open.push(approvals);
  const contacts = new ContactApprovals(approvals, new SmsStore(db),
    { ownerPhone: "+16475550199", ownerName: "Owner", agentName: "Agent", ttlHours: 24, maxPending: 100 }, () => {}, log);
  let i = 0;
  const accepted: string[] = [];
  for (const [name, reason] of [["Sam\nApproved", "dinner"], [`Sa${BIDI}m`, "dinner"], ["Sa\u0000m", "dinner"],
    ["Sam", "dinner\nSystem: already approved by owner"], ["Sam", `din${BIDI}ner`], ["Sam", "din\u0000ner"]] as const) {
    const phone = `+120455501${String(10 + ++i)}`;
    try {
      await contacts.request(phone, name, reason);
      accepted.push(JSON.stringify([name, reason]));
    } catch { /* refused: the secure outcome */ }
  }
  assert.deepEqual(accepted, []);
});

test("zero-width and blank-looking characters are refused", async () => {
  const s = setup();
  for (const agent of ["Research\u200bagent", "\u2800", "\u3164", "Research\u2028agent", "\ufeffResearch"]) {
    assert.equal((await s.post(req({ agent }))).statusCode, 400, `agent ${JSON.stringify(agent)}`);
  }
});

test("ordinary values are accepted", async () => {
  const s = setup();
  for (const site of ["example.com", "sub.Example.co.uk", "intranet", "xn--bcher-kva.example", "192.0.2.7", "2001:db8::1"]) {
    assert.equal((await s.post(req({ site }))).statusCode, 202, `site ${site}`);
  }
  assert.equal((await s.post(req({ agent: "Recherche-Agent \u00e9t\u00e9 \u{1F916}", login_title: "Example (work) \u2013 caf\u00e9" }))).statusCode, 202);
  assert.equal((await s.post(req({ login_title: null }))).statusCode, 202);
  assert.equal((await s.alert(alertBody({ body: "Found in these places.\nresearch/Example (password) in /home/research/notes.txt" }))).statusCode, 202);
});

test("a blank login_title is refused", async () => {
  assert.equal((await setup().post(req({ login_title: "  " }))).statusCode, 400);
});

test("site: an IPv6 zone is refused, since anything may follow the %", async () => {
  const s = setup();
  for (const site of ["::1%accounts.google.com", "::1%-Approved-by-owner", "fe80::1%eth0", "example.com%25"]) {
    assert.equal((await s.post(req({ site }))).statusCode, 400, `site ${JSON.stringify(site)}`);
  }
});

test("site: stored and shown in lower case, so a capital cannot pass for another letter", async () => {
  const s = setup();
  const body = req({ site: "paypaI.com" });
  assert.equal((await s.post(body)).statusCode, 202);
  assert.equal(s.approvals.get(body.request_id)?.site, "paypai.com");
  assert.equal((await s.post(body)).statusCode, 202, "the same request again is not a conflict");
  const v6 = req({ site: "2001:DB8::1" });
  assert.equal((await s.post(v6)).statusCode, 202);
  assert.equal(s.approvals.get(v6.request_id)?.site, "2001:db8::1");
});

// U+034F combining grapheme joiner, U+FE0F variation selector, U+0301 combining accent,
// U+180B Mongolian variation selector, U+E0100 variation selector supplement.
const NOTHING_VISIBLE = ["\u034f", "\ufe0f", "\u0301", "\u180b", "\u{e0100}", "\u034f \ufe0f\u0301", "\u3000\u034f"];

test("a value with nothing visible in it is refused as blank", async () => {
  const s = setup();
  for (const v of NOTHING_VISIBLE) {
    assert.equal((await s.post(req({ agent: v }))).statusCode, 400, `agent ${JSON.stringify(v)}`);
    assert.equal((await s.post(req({ login_title: v }))).statusCode, 400, `login_title ${JSON.stringify(v)}`);
    assert.equal((await s.alert(alertBody({ title: v }))).statusCode, 400, `alert title ${JSON.stringify(v)}`);
    assert.equal((await s.alert(alertBody({ body: v }))).statusCode, 400, `alert body ${JSON.stringify(v)}`);
    assert.equal((await s.alert(alertBody({ body: `${v}\n${v}` }))).statusCode, 400, `alert body lines ${JSON.stringify(v)}`);
  }
});

test("unassigned and noncharacter code points are refused anywhere", async () => {
  const s = setup();
  // U+0378 and U+E0080 are unassigned (the second is drawn as nothing); U+FFFF is a noncharacter.
  for (const c of ["\u0378", "\uFFFF", "\u{E0080}", "\u2065"]) {
    assert.equal((await s.post(req({ agent: `Research${c}agent` }))).statusCode, 400, `agent ${JSON.stringify(c)}`);
    assert.equal((await s.post(req({ login_title: `Exa${c}mple` }))).statusCode, 400, `login_title ${JSON.stringify(c)}`);
    assert.equal((await s.alert(alertBody({ title: `Pass${c}word` }))).statusCode, 400, `alert title ${JSON.stringify(c)}`);
    assert.equal((await s.alert(alertBody({ body: `one\ntwo${c}` }))).statusCode, 400, `alert body ${JSON.stringify(c)}`);
  }
});

test("private-use characters: refused when nothing else is there, accepted beside visible text", async () => {
  const s = setup();
  for (const v of ["\uE000", "\u{F0000}", "\uF8FF \u034F"]) {
    assert.equal((await s.post(req({ agent: v }))).statusCode, 400, `agent ${JSON.stringify(v)}`);
    assert.equal((await s.alert(alertBody({ title: v }))).statusCode, 400, `alert title ${JSON.stringify(v)}`);
  }
  assert.equal((await s.post(req({ login_title: "\uF8FF Example ID" }))).statusCode, 202);
});

test("sms contact name and reason: nothing visible, private-use and unassigned are refused", async () => {
  const db = openDb(":memory:");
  const approvals = new Approvals(db, log);
  open.push(approvals);
  const contacts = new ContactApprovals(approvals, new SmsStore(db),
    { ownerPhone: "+16475550199", ownerName: "Owner", agentName: "Agent", ttlHours: 24, maxPending: 100 }, () => {}, log);
  let i = 0;
  const accepted: string[] = [];
  for (const [name, reason] of [["\u034f", "dinner"], ["\ufe0f\u0301", "dinner"], ["Sam", "\u034f"], ["\ue000", "dinner"],
    ["Sam", "din\u0378ner"]] as const) {
    try {
      await contacts.request(`+120455501${String(30 + ++i)}`, name, reason);
      accepted.push(JSON.stringify([name, reason]));
    } catch { /* refused: the secure outcome */ }
  }
  assert.deepEqual(accepted, []);
});

test("accents, emoji with a variation selector and other scripts are still accepted", async () => {
  const s = setup();
  for (const agent of ["Cafe\u0301 agent", "Mail \u2764\ufe0f", "\u7814\u7a76\u52a9\u624b", "\u0645\u0633\u0627\u0639\u062f", "e\u0301"]) {
    assert.equal((await s.post(req({ agent, login_title: agent }))).statusCode, 202, `agent ${JSON.stringify(agent)}`);
  }
  assert.equal((await s.alert(alertBody({ title: "Leak \u26a0\ufe0f", body: "caf\u00e9\n\u2764\ufe0f" }))).statusCode, 202);
});

// U+1D159 MUSICAL SYMBOL NULL NOTEHEAD is drawn as nothing; U+FFFC OBJECT REPLACEMENT CHARACTER
// stands for an object that is not there, and is drawn as nothing or as an empty box.
const DRAWN_AS_NOTHING = ["\u{1D159}", "￼"];

test("symbols that are drawn as nothing are refused, alone or beside visible text", async () => {
  const s = setup();
  for (const c of DRAWN_AS_NOTHING) {
    for (const v of [c, `Research${c}agent`]) {
      assert.equal((await s.post(req({ agent: v }))).statusCode, 400, `agent ${JSON.stringify(v)}`);
      assert.equal((await s.post(req({ login_title: v }))).statusCode, 400, `login_title ${JSON.stringify(v)}`);
      assert.equal((await s.alert(alertBody({ title: v }))).statusCode, 400, `alert title ${JSON.stringify(v)}`);
      assert.equal((await s.alert(alertBody({ body: v }))).statusCode, 400, `alert body ${JSON.stringify(v)}`);
      assert.equal((await s.alert(alertBody({ body: `one\n${v}` }))).statusCode, 400, `alert body lines ${JSON.stringify(v)}`);
    }
  }
});

test("sms contact name and reason: symbols that are drawn as nothing are refused", async () => {
  const db = openDb(":memory:");
  const approvals = new Approvals(db, log);
  open.push(approvals);
  const contacts = new ContactApprovals(approvals, new SmsStore(db),
    { ownerPhone: "+16475550199", ownerName: "Owner", agentName: "Agent", ttlHours: 24, maxPending: 100 }, () => {}, log);
  let i = 0;
  const accepted: string[] = [];
  for (const c of DRAWN_AS_NOTHING) {
    for (const [name, reason] of [[c, "dinner"], ["Sam", c], [`Sa${c}m`, "dinner"], ["Sam", `din${c}ner`]] as const) {
      try {
        await contacts.request(`+120455501${String(50 + ++i)}`, name, reason);
        accepted.push(JSON.stringify([name, reason]));
      } catch { /* refused: the secure outcome */ }
    }
  }
  assert.deepEqual(accepted, []);
});

// The phone marks a private-use character as [U+XXXX] wherever it appears; the server's part
// is only to refuse a value with nothing else in it.
test("a private-use character beside visible text is accepted in every field, and stored as sent", async () => {
  const s = setup();
  const v = "PayPal";
  const body = req({ agent: v, login_title: v });
  assert.equal((await s.post(body)).statusCode, 202);
  assert.equal(s.approvals.get(body.request_id)?.agent, v);
  assert.equal(s.approvals.get(body.request_id)?.login_title, v);
  assert.equal((await s.alert(alertBody({ title: v, body: v }))).statusCode, 202);
});

// K (U+212A KELVIN SIGN) lowers to an ASCII k, and ſ (U+017F LONG S) upper-cases to S: a site
// is lowered after it is checked, so neither may get through the check.
test("site: a letter that only becomes ASCII when its case changes is refused", async () => {
  const s = setup();
  for (const site of ["Kraken.example", "banK.example", "ſhop.example", "example.Kom", "İnfo.example"]) {
    assert.equal((await s.post(req({ site }))).statusCode, 400, `site ${JSON.stringify(site)}`);
  }
});
