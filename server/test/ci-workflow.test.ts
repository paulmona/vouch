import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

const FILE = new URL("../../.github/workflows/ci.yml", import.meta.url);
const text = (): string => readFileSync(FILE, "utf8");
const step = (name: string): string => {
  const all = text().split(/^ {6}- /m);
  const found = all.find((s) => s.startsWith(`name: ${name}\n`));
  assert.ok(found, `ci.yml has no step named ${name}`);
  return found;
};

// The step's own script, run here against a small repository: which parts a change sets off.
function changed(event: string, files: string[]): Set<string> {
  const script = step("What changed").split(/^ {8}run: \|\n/m)[1]!.replace(/^ {10}/gm, "");
  assert.doesNotMatch(script, /\$\{\{/, "the script still needs GitHub to fill something in");
  const dir = mkdtempSync(join(tmpdir(), "vouch-ci-"));
  try {
    const git = (...a: string[]): string => {
      const r = spawnSync("git", ["-c", "user.name=t", "-c", "user.email=t@example.com", "-c", "commit.gpgsign=false", ...a], { cwd: dir, encoding: "utf8" });
      assert.equal(r.status, 0, r.stderr);
      return r.stdout.trim();
    };
    git("init", "-q");
    git("commit", "-q", "--allow-empty", "-m", "base");
    const base = git("rev-parse", "HEAD");
    for (const f of files) {
      mkdirSync(join(dir, f, ".."), { recursive: true });
      writeFileSync(join(dir, f), "x\n");
    }
    git("add", "-A");
    git("commit", "-q", "--allow-empty", "-m", "change");
    const out = join(dir, ".out");
    const r = spawnSync("bash", ["-e", "-c", script], { cwd: dir, encoding: "utf8", env: { ...process.env, EVENT: event, BASE: base, GITHUB_OUTPUT: out } });
    assert.equal(r.status, 0, r.stderr);
    return new Set(existsSync(out) ? readFileSync(out, "utf8").split("\n").filter((l) => l.endsWith("=true")).map((l) => l.split("=")[0]!) : []);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

// Two pull requests that each pass alone can fail together: the first place that shows is main.
test("CI runs every part on a push to main", (t) => {
  if (!existsSync(FILE)) return t.skip("not a full checkout");
  if (spawnSync("git", ["--version"]).status !== 0) return t.skip("no git");
  assert.match(text(), /^on:\n(?: {2}.*\n)* {2}push:\n {4}branches: \[main\]\n/m, "ci.yml does not run on a push to main");
  assert.deepEqual([...changed("push", ["docs/a.md"])].sort(), ["api", "app", "broker", "server"]);
  assert.deepEqual([...changed("schedule", [])].sort(), ["api", "app", "broker", "server"]);
});

// The server's tests read the documents, the workflows and the whole tree.
test("the server's tests run on every pull request, whatever it touches", (t) => {
  if (!existsSync(FILE)) return t.skip("not a full checkout");
  for (const name of ["Server lint, typecheck, tests, audit"]) {
    const s = step(name);
    assert.doesNotMatch(s, /steps\.changed/, `${name} is skipped when a pull request leaves server/ alone`);
    assert.match(s, /^\s+npm test$/m);
  }
  const node = text().split(/^ {6}- /m).find((s) => s.startsWith("uses: actions/setup-node@"));
  assert.ok(node && !/steps\.changed/.test(node), "Node is not set up when a pull request leaves server/ alone");
});

// Each part ships its own copy of LICENSE and NOTICE and tests that copy.
test("a change to LICENSE or NOTICE runs every part's checks", (t) => {
  if (!existsSync(FILE)) return t.skip("not a full checkout");
  if (spawnSync("git", ["--version"]).status !== 0) return t.skip("no git");
  for (const f of ["LICENSE", "NOTICE"]) {
    const set = changed("pull_request", [f]);
    for (const part of ["app", "broker", "server"]) assert.ok(set.has(part), `a change to ${f} does not run the ${part} checks`);
  }
  assert.deepEqual([...changed("pull_request", ["docs/NOTICE"])], [], "only the two files at the top are meant");
  assert.deepEqual([...changed("pull_request", ["app/lib/a.dart"])], ["app"]);
  assert.deepEqual([...changed("pull_request", ["browser/setup"])], ["broker"]);
});

test("the broker's tests run on every Python the broker says it supports", (t) => {
  if (!existsSync(FILE)) return t.skip("not a full checkout");
  const wants = readFileSync(new URL("../../broker/pyproject.toml", import.meta.url), "utf8").match(/^requires-python = ">=3\.(\d+),<3\.(\d+)"$/m);
  assert.ok(wants, "broker/pyproject.toml no longer gives a range this test can read");
  const versions = Array.from({ length: Number(wants[2]) - Number(wants[1]) }, (_, i) => `3.${Number(wants[1]) + i}`);
  const s = step("Broker lint, tests, audit");
  const loop = s.match(/for py in ([\d. ]+); do uv run --frozen --python "\$py" pytest -q; done/);
  assert.ok(loop, "the broker's tests do not run once for each Python");
  assert.deepEqual(loop[1]!.split(" "), versions);
});
