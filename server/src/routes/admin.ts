import type { FastifyInstance } from "fastify";
import type { Config } from "../config.ts";
import type { Device, Devices } from "../devices.ts";

// The pairing link in the QR code. The app reads `server` (the app API's base
// URL) and `token` (the setup token); `v` is this format's version.
export function pairUrl(server: string, token: string): string {
  return `vouch://pair?${new URLSearchParams({ v: "1", server, token })}`;
}

const summary = (d: Device) => ({ device_id: d.device_id, name: d.name, platform: d.platform,
  user_auth_bound: d.user_auth_bound, security_level: d.security_level, paired_at: d.paired_at,
  revoked_at: d.revoked_at, last_checkin_at: d.last_checkin_at, push: d.push_token !== "" });

// Owner-only socket for the `vouch` CLI.
export function adminRoutes(app: FastifyInstance, { config, devices }: { config: Config; devices: Devices }): void {
  app.post("/v1/setup-codes", async (_req, reply) => {
    if (!config.app.publicUrl) {
      return reply.code(409).send({ code: "bad_request",
        message: "Set app.public_url in the config first: the phone needs to know where to reach this server." });
    }
    const { token, expires_at } = devices.createSetupToken();
    return reply.code(201).send({ setup_token: token, expires_at, pair_url: pairUrl(config.app.publicUrl, token) });
  });

  app.get("/v1/devices", async () => devices.list().map(summary));

  app.post<{ Params: { id: string } }>("/v1/devices/:id/unpair", async (req, reply) => {
    const d = devices.unpair(req.params.id);
    return d ? summary(d) : reply.code(404).send({ code: "not_found", message: "No device with that id." });
  });
}
