import { pino, type Logger } from "pino";

// Every line carries ts, service and event. Secrets are redacted as a backstop,
// not as the plan: nothing should log one in the first place.
export function createLogger(level: string, destination?: pino.DestinationStream): Logger {
  return pino(
    {
      level,
      base: { service: "approver" },
      messageKey: "event",
      timestamp: () => `,"ts":"${new Date().toISOString()}"`,
      formatters: { level: (label) => ({ level: label }) },
      redact: {
        paths: ["push_token", "*.push_token", "setup_token", "*.setup_token", "password", "*.password", "username", "*.username"],
        censor: "[redacted]",
      },
    },
    destination,
  );
}

export type { Logger };
