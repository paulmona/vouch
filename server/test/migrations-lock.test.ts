import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readdirSync, readFileSync } from "node:fs";
import { test } from "node:test";
import { MIGRATIONS_DIR } from "../src/db.ts";

// A migration that has run anywhere must never change: the server refuses to
// start against a database that recorded a different hash (an edit to a comment
// in 0006 once took production down). migrations.lock records each file's hash.
test("released migrations are byte-for-byte unchanged, and every migration is in migrations.lock", () => {
  const lock = new Map(readFileSync(new URL("../migrations.lock", import.meta.url), "utf8").trim().split("\n")
    .map((l) => l.split(/\s+/)).map(([sha, name]) => [name!, sha!]));
  for (const name of readdirSync(MIGRATIONS_DIR).filter((f) => f.endsWith(".sql"))) {
    const sha = createHash("sha256").update(readFileSync(`${MIGRATIONS_DIR}${name}`)).digest("hex");
    assert.ok(lock.has(name), `${name} is not in server/migrations.lock: add its sha256 when you add the migration`);
    assert.equal(sha, lock.get(name), `${name} was edited after release; migrations are append-only, add a new one instead`);
  }
});
