import { chmodSync, existsSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { parseArgs } from "node:util";
import { ApiError, FakeDevice, parsePairUrl, type Decision, type DeviceState } from "./fake-device/client.ts";

const USAGE = `usage: fake-device [--state FILE] <command>

A software phone for testing the approver. Its keys have no attestation, so the
server must run with policy.require_user_auth = false.

  pair <vouch://pair link>         pair, generating new keys
  pair --server URL <setup token>  the same, from the code \`vouch setup-code\` prints
  me                               this device as the server sees it
  pending                          list pending requests
  decide <request id> once|always|deny
  watch once|always|deny           answer every new request the same way, until stopped
  checkin [heartbeat id]           answer a heartbeat

options:
  --state FILE     keys and device id (default ~/.vouch-fake-device.json, mode 0600)
  --name NAME      device name when pairing (default "Fake device")
  --interval SECS  watch poll interval (default 2)`;

const { values, positionals } = parseArgs({
  allowPositionals: true,
  options: {
    state: { type: "string", default: join(homedir(), ".vouch-fake-device.json") },
    server: { type: "string" },
    name: { type: "string" },
    interval: { type: "string", default: "2" },
    help: { type: "boolean", short: "h" },
  },
});

const DECISIONS = ["once", "always", "deny"];
const asDecision = (s: string | undefined): Decision => {
  if (!s || !DECISIONS.includes(s)) usage();
  return s as Decision;
};

function usage(): never {
  console.error(USAGE);
  process.exit(2);
}

function load(): FakeDevice {
  if (!existsSync(values.state)) throw new Error(`${values.state} not found: pair first`);
  return new FakeDevice(JSON.parse(readFileSync(values.state, "utf8")) as DeviceState);
}

const line = (r: { request_id: string; agent: string; site: string; state: string; expires_at: string }) =>
  [r.request_id, r.agent, r.site, r.state, `expires ${r.expires_at}`].join("  ");

const [command, ...args] = positionals;
try {
  if (values.help || !command) {
    console.log(USAGE);
  } else if (command === "pair" && args[0]) {
    const { server, token } = values.server ? { server: values.server, token: args[0] } : parsePairUrl(args[0]);
    const { device, response } = await FakeDevice.pair(server, token, { name: values.name });
    writeFileSync(values.state, JSON.stringify(device.state, null, 2) + "\n", { mode: 0o600 });
    chmodSync(values.state, 0o600);
    console.log(`Paired with ${response.server_name} as ${response.device_id} (user_auth_bound ${response.user_auth_bound}).`);
  } else if (command === "me") {
    console.log(JSON.stringify(await load().me(), null, 2));
  } else if (command === "pending") {
    const requests = await load().pending(50);
    if (requests.length === 0) console.log("No pending requests.");
    for (const r of requests) console.log(line(r));
  } else if (command === "decide" && args[0]) {
    console.log(line(await load().decide(args[0], asDecision(args[1]))));
  } else if (command === "watch") {
    const decision = asDecision(args[0]);
    const device = load();
    const seen = new Set<string>();
    console.log(`Answering "${decision}" to every new request. Ctrl-C to stop.`);
    for (;;) {
      for (const r of await device.pending(50)) {
        if (seen.has(r.request_id)) continue;
        seen.add(r.request_id);
        await device.request(r.request_id);
        try {
          console.log(line(await device.decide(r.request_id, decision)));
        } catch (e) {
          console.log(`${r.request_id}  ${(e as Error).message}`);
        }
      }
      await new Promise((resolve) => setTimeout(resolve, Number(values.interval) * 1000));
    }
  } else if (command === "checkin") {
    await load().checkin(args[0] ?? null);
    console.log("Checked in.");
  } else {
    usage();
  }
} catch (e) {
  const hint = e instanceof ApiError && e.code === "policy_requires_user_auth"
    ? "\nThis server requires attested keys; a fake device needs policy.require_user_auth = false." : "";
  console.error(`fake-device: ${(e as Error).message}${hint}`);
  process.exit(1);
}
