import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { MIGRATIONS_DIR, migrate, openDb } from "../src/db.ts";

function dir(files: Record<string, string>): string {
  const d = mkdtempSync(join(tmpdir(), "vouch-mig-"));
  for (const [name, sql] of Object.entries(files)) writeFileSync(join(d, name), sql);
  return d;
}

test("applies migrations in order, once", () => {
  const d = dir({ "0002_b.sql": "ALTER TABLE t ADD COLUMN b TEXT;", "0001_a.sql": "CREATE TABLE t (a TEXT);" });
  const db = new DatabaseSync(":memory:");
  assert.deepEqual(migrate(db, d), ["0001_a.sql", "0002_b.sql"]);
  assert.deepEqual(migrate(db, d), []);
  db.prepare("INSERT INTO t (a, b) VALUES ('x', 'y')").run();
  rmSync(d, { recursive: true });
});

test("refuses an edited, missing or back-dated migration", () => {
  const d = dir({ "0001_a.sql": "CREATE TABLE t (a TEXT);", "0003_c.sql": "CREATE TABLE c (c TEXT);" });
  const db = new DatabaseSync(":memory:");
  migrate(db, d);
  writeFileSync(join(d, "0002_b.sql"), "CREATE TABLE b (b TEXT);");
  assert.throws(() => migrate(db, d), /0002_b\.sql is older than the newest applied one/);
  rmSync(join(d, "0002_b.sql"));
  writeFileSync(join(d, "0001_a.sql"), "CREATE TABLE t (a TEXT, z TEXT);");
  assert.throws(() => migrate(db, d), /0001_a\.sql was edited/);
  rmSync(join(d, "0001_a.sql"));
  assert.throws(() => migrate(db, d), /0001_a\.sql is missing/);
  rmSync(d, { recursive: true });
});

test("a failing migration leaves nothing behind", () => {
  const d = dir({ "0001_a.sql": "CREATE TABLE t (a TEXT); INSERT INTO nope VALUES (1);" });
  const db = new DatabaseSync(":memory:");
  assert.throws(() => migrate(db, d), /0001_a\.sql failed/);
  assert.equal(db.prepare("SELECT count(*) n FROM sqlite_master WHERE name = 't'").get()?.n, 0);
  assert.equal(db.prepare("SELECT count(*) n FROM migrations").get()?.n, 0);
  rmSync(d, { recursive: true });
});

test("refuses badly named files", () => {
  const d = dir({ "1_a.sql": "" });
  assert.throws(() => migrate(new DatabaseSync(":memory:"), d), /must be named NNNN_name\.sql/);
  rmSync(d, { recursive: true });
});

test("the shipped migrations apply to a new database", () => {
  const d = mkdtempSync(join(tmpdir(), "vouch-db-"));
  openDb(join(d, "a.db"), MIGRATIONS_DIR).close();
  rmSync(d, { recursive: true });
});
