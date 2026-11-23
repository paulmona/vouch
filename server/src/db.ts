import { createHash } from "node:crypto";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";

export const MIGRATIONS_DIR = new URL("../migrations/", import.meta.url).pathname;

export function openDb(path: string, migrationsDir = MIGRATIONS_DIR): DatabaseSync {
  const db = new DatabaseSync(path);
  // secure_delete: deleted SMS text is overwritten, not left in free pages.
  db.exec("PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON; PRAGMA busy_timeout = 5000; PRAGMA secure_delete = ON;");
  migrate(db, migrationsDir);
  return db;
}

// Migrations are append-only: files named NNNN_name.sql, applied in order, each
// recorded with its hash. An applied migration that was edited or removed stops
// startup, because the database no longer matches what the code expects.
export function migrate(db: DatabaseSync, dir: string): string[] {
  db.exec(`CREATE TABLE IF NOT EXISTS migrations (
    id INTEGER PRIMARY KEY, name TEXT NOT NULL, sha256 TEXT NOT NULL, applied_at TEXT NOT NULL)`);
  const files = readdirSync(dir).filter((f) => f.endsWith(".sql")).sort();
  const onDisk = new Map<number, { name: string; sql: string; sha256: string }>();
  for (const name of files) {
    const m = /^(\d{4})_[a-z0-9_]+\.sql$/.exec(name);
    if (!m) throw new Error(`migration ${name} must be named NNNN_name.sql`);
    const id = Number(m[1]);
    if (onDisk.has(id)) throw new Error(`two migrations numbered ${m[1]}`);
    const sql = readFileSync(join(dir, name), "utf8");
    onDisk.set(id, { name, sql, sha256: createHash("sha256").update(sql).digest("hex") });
  }
  const applied = db.prepare("SELECT id, name, sha256 FROM migrations ORDER BY id").all() as
    { id: number; name: string; sha256: string }[];
  for (const row of applied) {
    const file = onDisk.get(row.id);
    if (!file) throw new Error(`applied migration ${row.name} is missing`);
    if (file.sha256 !== row.sha256) throw new Error(`applied migration ${row.name} was edited`);
  }
  const last = applied.at(-1)?.id ?? 0;
  const ran: string[] = [];
  for (const [id, file] of [...onDisk].sort(([a], [b]) => a - b)) {
    if (id <= last) {
      if (!applied.some((r) => r.id === id)) throw new Error(`migration ${file.name} is older than the newest applied one`);
      continue;
    }
    db.exec("BEGIN");
    try {
      db.exec(file.sql);
      db.prepare("INSERT INTO migrations (id, name, sha256, applied_at) VALUES (?, ?, ?, ?)")
        .run(id, file.name, file.sha256, new Date().toISOString());
      db.exec("COMMIT");
    } catch (e) {
      db.exec("ROLLBACK");
      throw new Error(`migration ${file.name} failed: ${(e as Error).message}`, { cause: e });
    }
    ran.push(file.name);
  }
  return ran;
}
