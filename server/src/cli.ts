import { randomBytes } from "node:crypto";
import { request } from "node:http";
import { parseArgs } from "node:util";
import { renderUnicodeCompact } from "uqr";

const USAGE = `usage: vouch [--socket PATH] [--broker-socket PATH] <command>

  setup-code         make a single-use pairing code (valid 10 minutes) and show its QR
  devices            list paired devices
  unpair <id>        unpair a device
  send-test-request  ask paired phones to approve a made-up sign-in, and wait for the answer
                     (--agent NAME, --site HOST, --ttl SECONDS; default Test agent,
                     example.com, 120). For test instances: it goes through the broker socket.`;

const { values, positionals } = parseArgs({
  allowPositionals: true,
  options: {
    socket: { type: "string", default: "/run/vouch/admin.sock" },
    "broker-socket": { type: "string", default: "/run/vouch/broker.sock" },
    agent: { type: "string", default: "Test agent" },
    site: { type: "string", default: "example.com" },
    ttl: { type: "string", default: "120" },
    help: { type: "boolean", short: "h" },
  },
});

type Body = Record<string, unknown> & unknown[];

function call(method: string, path: string, body?: object, socketPath = values.socket): Promise<{ status: number; body: Body }> {
  return new Promise((resolve, reject) => {
    const req = request({ socketPath, method, path, headers: body ? { "content-type": "application/json" } : {} }, (res) => {
      let data = "";
      res.on("data", (c) => (data += c)).on("end", () => resolve({ status: res.statusCode!, body: JSON.parse(data || "null") }));
    }).on("error", (e: NodeJS.ErrnoException) => {
      reject(new Error(e.code === "EACCES" ? `${socketPath}: permission denied (run as the vouch user)`
        : e.code === "ENOENT" ? `${socketPath} not found: is the approver running?` : e.message));
    });
    req.end(body ? JSON.stringify(body) : undefined);
  });
}

function fail(message: string): never {
  console.error(`vouch: ${message}`);
  process.exit(1);
}

async function sendTestRequest(): Promise<void> {
  const broker = values["broker-socket"];
  const ttl = Number(values.ttl);
  if (!(ttl > 0 && ttl <= 3600)) fail("--ttl must be 1 to 3600 seconds");
  const id = `req_test_${randomBytes(9).toString("base64url")}`;
  const r = await call("POST", "/v1/approvals", { request_id: id, kind: "sign_in", agent: values.agent, site: values.site,
    login_title: `${values.site} (test)`, expires_at: new Date(Date.now() + ttl * 1000).toISOString() }, broker);
  if (r.status !== 202) fail(String(r.body.message));
  console.log(`Sent ${id}: ${values.agent} wants to sign in to ${values.site}. Waiting up to ${ttl} s for an answer.`);
  for (;;) {
    const s = await call("GET", `/v1/approvals/${id}?wait=30`, undefined, broker);
    if (s.body.state !== "pending") {
      console.log(`${s.body.state}${s.body.device_id ? ` by ${s.body.device_id}` : ""}`);
      return;
    }
  }
}

const [command, arg] = positionals;
try {
  if (values.help || !command) {
    console.log(USAGE);
  } else if (command === "setup-code") {
    const r = await call("POST", "/v1/setup-codes");
    if (r.status !== 201) fail(String(r.body.message));
    console.log(renderUnicodeCompact(String(r.body.pair_url), { ecc: "M", border: 2 }));
    console.log(`\nScan with Vouch, or enter the code: ${r.body.setup_token}`);
    console.log(`Pairing link: ${r.body.pair_url}`);
    if (String(r.body.pair_url).includes("server=http%3A")) {
      console.log("Warning: this server's address is plain http. Fine for testing on your own network; use https otherwise.");
    }
    console.log(`Valid until ${new Date(String(r.body.expires_at)).toLocaleString(undefined, { timeZoneName: "short" })}, for one device.`);
  } else if (command === "devices") {
    const r = await call("GET", "/v1/devices");
    if (r.body.length === 0) console.log("No devices paired.");
    for (const d of r.body as Record<string, string | boolean>[]) {
      console.log([d.device_id, d.name, d.platform, d.user_auth_bound, d.revoked_at ? `unpaired ${d.revoked_at}` : `paired ${d.paired_at}`,
        ...(d.push === false ? ["no push"] : [])].join("  "));
    }
  } else if (command === "unpair" && arg) {
    const r = await call("POST", `/v1/devices/${encodeURIComponent(arg)}/unpair`);
    if (r.status !== 200) fail(String(r.body.message));
    console.log(`Unpaired ${r.body.name} (${r.body.device_id}).`);
  } else if (command === "send-test-request") {
    await sendTestRequest();
  } else {
    console.error(USAGE);
    process.exit(2);
  }
} catch (e) {
  fail((e as Error).message);
}
