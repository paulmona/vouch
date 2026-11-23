import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

const SCRIPT = fileURLToPath(new URL("../../.github/check-signoff.sh", import.meta.url));
const CI = new URL("../../.github/workflows/ci.yml", import.meta.url);
const CONTRIBUTING = new URL("../../CONTRIBUTING.md", import.meta.url);

function repo() {
  const dir = mkdtempSync(join(tmpdir(), "signoff-"));
  const git = (...args: string[]) =>
    execFileSync("git", ["-c", "user.name=Sam Example", "-c", "user.email=sam@example.com", "-c", "commit.gpgsign=false", ...args],
      { cwd: dir, encoding: "utf8" }).trim();
  git("init", "-q", "-b", "main");
  git("commit", "-q", "--allow-empty", "-m", "base");
  return { dir, git, check: (base: string, head = "HEAD") => spawnSync(SCRIPT, [base, head], { cwd: dir, encoding: "utf8" }) };
}

test("the sign-off check refuses a pull request with a commit that is not signed off", (t) => {
  if (!existsSync(SCRIPT)) return t.skip("not a full checkout");
  const { dir, git, check } = repo();
  try {
    const base = git("rev-parse", "HEAD");
    git("commit", "-q", "--allow-empty", "-s", "-m", "signed");
    assert.equal(check(base).status, 0, "a signed-off commit was refused");
    git("commit", "-q", "--allow-empty", "-m", "not signed\n\nSigned-off-by: in the body, with no name and address");
    const r = check(base);
    assert.equal(r.status, 1, "an unsigned commit passed");
    assert.match(r.stdout, /No Signed-off-by line: [0-9a-f]+ not signed/);
    assert.doesNotMatch(r.stdout, /[0-9a-f]+ signed$/m, "the signed commit was reported too");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("the sign-off check does not ask for a sign-off on a merge commit", (t) => {
  if (!existsSync(SCRIPT)) return t.skip("not a full checkout");
  const { dir, git, check } = repo();
  try {
    const base = git("rev-parse", "HEAD");
    git("checkout", "-q", "-b", "side");
    git("commit", "-q", "--allow-empty", "-s", "-m", "side");
    git("checkout", "-q", "main");
    git("commit", "-q", "--allow-empty", "-s", "-m", "main moves");
    git("merge", "-q", "--no-ff", "-m", "merge side", "side");
    assert.equal(check(base).status, 0);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

// main moved after the branch was cut, by a squash merge that carries no sign-off. Those are not the pull request's commits.
test("the sign-off check, run as CI runs it, does not count commits main gained after the branch was cut", (t) => {
  if (!existsSync(SCRIPT)) return t.skip("not a full checkout");
  const { dir, git, check } = repo();
  try {
    const cut = git("rev-parse", "HEAD");
    git("checkout", "-q", "-b", "side");
    git("commit", "-q", "--allow-empty", "-s", "-m", "side");
    git("checkout", "-q", "main");
    git("commit", "-q", "--allow-empty", "-m", "main moves, not signed");
    git("checkout", "-q", "--detach");
    git("merge", "-q", "--no-ff", "-m", "what CI checks out", "side");
    assert.equal(check(cut).status, 1, "the old range no longer shows the fault this test is for");
    const r = check("HEAD^1", "HEAD^2");
    assert.equal(r.status, 0, r.stdout);
    git("checkout", "-q", "side");
    git("commit", "-q", "--allow-empty", "-m", "side, not signed");
    git("checkout", "-q", "--detach", "main");
    git("merge", "-q", "--no-ff", "-m", "what CI checks out", "side");
    assert.equal(check("HEAD^1", "HEAD^2").status, 1, "an unsigned commit on the branch passed");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("the sign-off check fails when it cannot list the commits", (t) => {
  if (!existsSync(SCRIPT)) return t.skip("not a full checkout");
  const { dir, check } = repo();
  try {
    const r = check("no-such-commit");
    assert.notEqual(r.status, 0, "a range git could not read passed as signed off");
    assert.doesNotMatch(r.stdout, /Every commit is signed off/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("CI runs the sign-off check on pull requests, and CONTRIBUTING.md asks for it", (t) => {
  if (!existsSync(CI)) return t.skip("not a full checkout");
  const ci = readFileSync(CI, "utf8");
  // HEAD on a pull request is GitHub's merge of the branch into main: parent 1 is main now, parent 2 the branch.
  assert.match(ci, /if: github\.event_name == 'pull_request'\n(?:\s+#.*\n)*\s+run: \.github\/check-signoff\.sh 'HEAD\^1' 'HEAD\^2'/);
  assert.doesNotMatch(ci, /check-signoff\.sh "\$BASE"/, "the range starts at the base recorded on the pull request, which lags when main moves");
  const doc = readFileSync(CONTRIBUTING, "utf8").replace(/\s+/g, " ");
  for (const must of ["Developer Certificate of Origin", "`git commit -s`", "Signed-off-by: Your Name <you@example.com>", "CI fails a pull request"]) {
    assert.ok(doc.includes(must), `CONTRIBUTING.md does not say: ${must}`);
  }
});
