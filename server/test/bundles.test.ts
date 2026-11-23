import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { copyFileSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

const ROOT = fileURLToPath(new URL("../../", import.meta.url));
const run = (cmd: string, args: string[], cwd: string) => spawnSync(cmd, args, { cwd, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
const has = (cmd: string): boolean => spawnSync(cmd, ["--version"]).status === 0;

// A copy of this checkout as git has it, with the bundle scripts as they are on disk now,
// and files of the kind the install guides have people create beside the tracked ones.
function checkoutWithLocalSecrets(planted: string[]): { dir: string; head: string } {
  const dir = mkdtempSync(join(tmpdir(), "vouch-bundle-"));
  const git = (...a: string[]): string => {
    const r = run("git", ["-c", "user.name=t", "-c", "user.email=t@example.com", "-c", "commit.gpgsign=false", ...a], dir);
    assert.equal(r.status, 0, r.stderr);
    return r.stdout.trim();
  };
  assert.equal(run("git", ["clone", "-q", "--no-hardlinks", ROOT, dir], ROOT).status, 0);
  for (const s of ["server/deploy/bundle.sh", "broker/deploy/bundle.sh"]) copyFileSync(join(ROOT, s), join(dir, s));
  git("commit", "-q", "--allow-empty", "-am", "the scripts under test");
  for (const f of planted) {
    mkdirSync(join(dir, f, ".."), { recursive: true });
    writeFileSync(join(dir, f), "NOT-A-REAL-SECRET\n");
    assert.equal(run("git", ["check-ignore", "-q", f], dir).status, 0, `${f} is not ignored, so this test proves nothing`);
  }
  return { dir, head: git("rev-parse", "HEAD") };
}

function built(dir: string, script: string): { names: string[]; tarball: string } {
  const out = join(dir, "out");
  const r = run(join(dir, script), [out], dir);
  assert.equal(r.status, 0, r.stderr);
  const tarball = r.stdout.trim().split("\n").at(-1)!;
  const list = run("tar", ["-tzf", tarball], dir);
  assert.equal(list.status, 0, list.stderr);
  return { names: list.stdout.split("\n").filter(Boolean).map((n) => n.split("/").slice(1).join("/")), tarball };
}

const fileIn = (tarball: string, name: string): string => {
  const top = run("tar", ["-tzf", tarball], ROOT).stdout.split("/")[0]!;
  return run("tar", ["-xzOf", tarball, `${top}/${name}`], ROOT).stdout;
};

// The guides have an installer put secrets.env and firebase.json under deploy/, where git
// ignores them. A bundle built on such a machine must hold only what git holds.
test("a server bundle holds only tracked files, whatever lies beside them", (t) => {
  if (run("git", ["rev-parse", "--git-dir"], ROOT).status !== 0) return t.skip("not a git checkout");
  const planted = ["server/deploy/docker/secrets.env", "server/deploy/docker/firebase.json", "server/deploy/prod/secrets.env", "server/deploy/docker/.env"];
  const { dir, head } = checkoutWithLocalSecrets(planted);
  try {
    const { names, tarball } = built(dir, "server/deploy/bundle.sh");
    for (const f of planted) assert.ok(!names.includes(f.replace(/^server\//, "")), `the bundle holds ${f}`);
    assert.ok(!run("tar", ["-xzOf", tarball], dir).stdout.includes("NOT-A-REAL-SECRET"), "a planted file's contents are in the bundle");
    for (const f of ["LICENSE", "NOTICE", "VERSION", "COMMIT", "package.json", "deploy/install.sh", "deploy/docker/compose.yaml", "src/main.ts", "node_modules/fastify/package.json"]) {
      assert.ok(names.includes(f), `the bundle is missing ${f}`);
    }
    assert.equal(fileIn(tarball, "COMMIT").trim(), head);
    assert.equal(fileIn(tarball, "VERSION").trim(), JSON.parse(readFileSync(join(dir, "server/package.json"), "utf8")).version);
    assert.equal(fileIn(tarball, "NOTICE"), readFileSync(join(dir, "NOTICE"), "utf8"));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a broker bundle holds only tracked files, whatever lies beside them", (t) => {
  if (run("git", ["rev-parse", "--git-dir"], ROOT).status !== 0) return t.skip("not a git checkout");
  if (!has("uv")) return t.skip("uv is not installed: the broker bundle cannot be built here");
  const planted = ["broker/deploy/secrets.env", "broker/deploy/vault/vault.env", "broker/deploy/.env"];
  const { dir, head } = checkoutWithLocalSecrets(planted);
  try {
    const { names, tarball } = built(dir, "broker/deploy/bundle.sh");
    for (const f of planted) assert.ok(!names.includes(f.replace(/^broker\//, "")), `the bundle holds ${f}`);
    assert.ok(!run("tar", ["-xzOf", tarball], dir).stdout.includes("NOT-A-REAL-SECRET"), "a planted file's contents are in the bundle");
    for (const f of ["LICENSE", "NOTICE", "VERSION", "COMMIT", "requirements.txt", "deploy/install.sh", "config.example.toml", "secrets.env.example"]) {
      assert.ok(names.includes(f), `the bundle is missing ${f}`);
    }
    assert.ok(names.some((n) => /^credbroker-.*\.whl$/.test(n)), "the bundle has no wheel");
    assert.equal(fileIn(tarball, "COMMIT").trim(), head);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

// A source distribution is an archive of broker/ alone. A link to ../LICENSE points at
// nothing once it is unpacked, so the two files have to be real ones.
test("the broker's LICENSE and NOTICE are files of its own, not links out of broker/", (t) => {
  if (!existsSync(join(ROOT, "broker/pyproject.toml"))) return t.skip("not a full checkout");
  for (const f of ["LICENSE", "NOTICE"]) {
    assert.ok(lstatSync(join(ROOT, "broker", f)).isFile(), `broker/${f} is a link: a source distribution would not carry the file`);
    assert.equal(readFileSync(join(ROOT, "broker", f), "utf8"), readFileSync(join(ROOT, f), "utf8"), `broker/${f} is not the repository's ${f}`);
  }
});

// The image's Dockerfile has its own allow-list, which only BuildKit reads. The same list
// at the top of the repository covers every other way the top can be sent as a build context.
test("the top of the repository has the image's allow-list too", (t) => {
  if (!existsSync(join(ROOT, "server/Dockerfile.dockerignore"))) return t.skip("not a full checkout");
  const rules = (p: string): string[] => readFileSync(join(ROOT, p), "utf8").split("\n").filter((l) => l && !l.startsWith("#"));
  assert.ok(existsSync(join(ROOT, ".dockerignore")), "no .dockerignore at the top of the repository");
  assert.deepEqual(rules(".dockerignore"), rules("server/Dockerfile.dockerignore"));
  assert.equal(rules(".dockerignore")[0], "*");
});
