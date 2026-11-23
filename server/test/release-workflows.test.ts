import assert from "node:assert/strict";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { test } from "node:test";

const DIR = new URL("../../.github/workflows/", import.meta.url);
const ON_MAIN = 'git merge-base --is-ancestor "$GITHUB_SHA" origin/main ||';

// A release tag can be pushed on any branch. A build that is signed or published must
// come from a commit on main, and the check has to run before any step is given a secret.
test("every release workflow refuses a tag that is not on main, before it uses a secret", (t) => {
  if (!existsSync(DIR)) return t.skip("not a full checkout");
  const releases = readdirSync(DIR).filter((f) => f.startsWith("release-"));
  assert.ok(releases.length >= 3, `found only ${releases.join(", ")}`);
  for (const f of releases) {
    const lines = readFileSync(new URL(f, DIR), "utf8").split("\n").filter((l) => !l.trim().startsWith("#"));
    const check = lines.findIndex((l) => l.includes(ON_MAIN));
    const secret = lines.findIndex((l) => /\$\{\{\s*(secrets\.|github\.token)/.test(l));
    assert.notEqual(check, -1, `${f} has no tag-on-main check`);
    assert.ok(secret === -1 || check < secret, `${f} uses a secret before it checks the tag is on main`);
    assert.match(lines.join("\n"), /fetch-depth: 0/, `${f} needs the full history for the check`);
  }
});

// A tag push runs the workflow file at the tagged commit, so a check written in that
// file protects nothing from whoever wrote the commit. The `release` environment is a
// repository setting: its reviewers and tag rules apply whatever the file says, and a
// secret stored there reaches only a job that names it.
test("every job in a release workflow runs in the release environment", (t) => {
  if (!existsSync(DIR)) return t.skip("not a full checkout");
  let jobs = 0;
  for (const f of readdirSync(DIR).filter((f) => f.startsWith("release-"))) {
    const text = readFileSync(new URL(f, DIR), "utf8");
    const body = text.slice(text.search(/^jobs:\s*$/m));
    const blocks = body.split(/^(?= {2}[\w-]+:\s*$)/m).slice(1);
    assert.ok(blocks.length >= 1, `${f} has no jobs`);
    for (const b of blocks) {
      const name = b.match(/^ {2}([\w-]+):/)![1];
      assert.match(b, /^ {4}environment: release\s*$/m, `${f}: job ${name} is not in the release environment`);
      jobs++;
    }
  }
  assert.ok(jobs >= 4, `found only ${jobs} release jobs`);
});

const steps = (job: string): string[] =>
  job.slice(job.search(/^ {4}steps:\s*$/m)).split("\n").slice(1).filter((l) => !/^\s*(#.*)?$/.test(l)).join("\n").split(/^ {6}- /m).slice(1);

// If the `release` environment does not exist when a tag is pushed, GitHub makes an empty
// one: no reviewer, no tag rule. A job that needs only the built-in token would then
// publish. Each job first looks for a variable that only the environment, once it has
// been set up, holds.
test("every release job stops first unless the release environment has been set up", (t) => {
  if (!existsSync(DIR)) return t.skip("not a full checkout");
  let jobs = 0;
  for (const f of readdirSync(DIR).filter((f) => f.startsWith("release-"))) {
    const text = readFileSync(new URL(f, DIR), "utf8");
    for (const job of text.slice(text.search(/^jobs:\s*$/m)).split(/^(?= {2}[\w-]+:\s*$)/m).slice(1)) {
      const name = job.match(/^ {2}([\w-]+):/)![1];
      const first = steps(job)[0] ?? "";
      assert.match(first, /READY: \$\{\{ vars\.RELEASE_ENV_READY \}\}/, `${f}: job ${name} does not start by checking the environment`);
      assert.match(first, /\[ "\$READY" = "true" \] \|\| \{[^}]*exit 1; \}/, `${f}: job ${name} does not stop when the environment is not set up`);
      assert.doesNotMatch(first, /^\s+(if|continue-on-error):/m, `${f}: job ${name}'s check can be skipped`);
      jobs++;
    }
  }
  assert.ok(jobs >= 4, `found only ${jobs} release jobs`);
  const guide = new URL("../../docs/maintaining.md", import.meta.url);
  assert.ok(existsSync(guide), "docs/maintaining.md is missing");
  const said = readFileSync(guide, "utf8").replace(/\s+/g, " ");
  for (const must of ["`RELEASE_ENV_READY`", "before you store any secret and before you push any tag", "Required reviewers",
    "`server-v*`", "`broker-v*`", "`app-v*`", "ANDROID_UPLOAD_KEYSTORE_B64", "ANDROID_KEYSTORE_PASSWORD", "ANDROID_KEY_ALIAS",
    "ANDROID_KEY_PASSWORD", "GOOGLE_SERVICES_JSON_B64", "Private vulnerability reporting", "Push protection", "Immutable releases",
    "`api-breaking`", "Run workflow", "before the first tag", "on a private one only on some paid plans", "nobody is asked first", "settings are not copied"]) {
    assert.ok(said.includes(must), `docs/maintaining.md does not say: ${must}`);
  }
  assert.match(readFileSync(new URL("../../CONTRIBUTING.md", import.meta.url), "utf8"), /docs\/maintaining\.md/, "CONTRIBUTING.md does not point to it");
});

test("the app release analyzes and tests the app before the signing key is on the runner", (t) => {
  if (!existsSync(DIR)) return t.skip("not a full checkout");
  const all = steps(readFileSync(new URL("release-app.yml", DIR), "utf8"));
  const secret = all.findIndex((s) => /\$\{\{\s*secrets\./.test(s));
  const tests = all.findIndex((s) => /^\s+flutter analyze$/m.test(s) && /^\s+flutter test$/m.test(s));
  assert.notEqual(tests, -1, "release-app.yml does not run flutter analyze and flutter test");
  assert.ok(tests < secret, "the app's tests run after a secret is used");
  assert.doesNotMatch(all[tests]!, /^\s+(if|continue-on-error):/m);
});
