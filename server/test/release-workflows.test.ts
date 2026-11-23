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
    "ANDROID_KEY_PASSWORD", "Private vulnerability reporting", "Push protection", "Immutable releases",
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

// There is no shared push relay: each installation pushes through its own Firebase project.
// A published app that carried the publisher's Firebase config would register every
// phone that installs it with the publisher's project. So the release is built with no
// Firebase config, and the finished APK is checked for one.
test("the published Android app is built without a Firebase config, and the APK is checked for one", (t) => {
  if (!existsSync(DIR)) return t.skip("not a full checkout");
  const text = readFileSync(new URL("release-app.yml", DIR), "utf8");
  const code = text.split("\n").filter((l) => !l.trim().startsWith("#")).join("\n");
  const all = steps(text.slice(text.search(/^jobs:\s*$/m)));
  assert.doesNotMatch(text, /GOOGLE_SERVICES_JSON_B64/, "release-app.yml still names the Firebase secret");
  assert.doesNotMatch(code, />\s*app\/android\/app\/google-services\.json/, "release-app.yml writes a Firebase config");
  const refuse = all.findIndex((s) => /\[ ! -e app\/android\/app\/google-services\.json \] \|\| \{[^}]*exit 1; \}/.test(s));
  const build = all.findIndex((s) => /flutter build apk --release/.test(s));
  const verify = all.findIndex((s) => /aapt2" dump resources/.test(s) && /google_app_id\|gcm_defaultSenderId\|google_api_key/.test(s) && /exit 1/.test(s));
  const publish = all.findIndex((s) => /gh release create/.test(s));
  assert.notEqual(refuse, -1, "nothing refuses a Firebase config that is already in the tree");
  assert.notEqual(verify, -1, "the APK is not checked for a Firebase config");
  assert.ok(refuse < build && build < verify && verify < publish, "the steps are out of order: refuse, build, check the APK, publish");
  for (const i of [refuse, verify]) assert.doesNotMatch(all[i]!, /^\s+(if|continue-on-error):/m, "a Firebase check can be skipped");
  for (const [file, must] of [["docs/maintaining.md", "built with no Firebase config"], ["app/README.md", "built with no Firebase config"]] as const) {
    const said = readFileSync(new URL(`../../${file}`, import.meta.url), "utf8").replace(/\s+/g, " ");
    assert.ok(said.includes(must), `${file} does not say: ${must}`);
    assert.ok(!said.includes("GOOGLE_SERVICES_JSON_B64"), `${file} still names the Firebase secret`);
  }
});

// The iPhone build is signed on a hosted Mac with a certificate and an upload key held in
// the `release` environment. The key must not be able to make anything in the Apple
// account, what signs must leave the runner, and the build must be the one that was tested.
test("the iPhone release tests first, signs with what it was given, and cleans up", (t) => {
  if (!existsSync(DIR)) return t.skip("not a full checkout");
  const file = new URL("release-ios.yml", DIR);
  assert.ok(existsSync(file), "release-ios.yml is missing");
  const text = readFileSync(file, "utf8");
  const code = text.split("\n").filter((l) => !l.trim().startsWith("#")).join("\n");
  const all = steps(text.slice(text.search(/^jobs:\s*$/m)));
  assert.match(code, /^on:\n {2}push:\n {4}tags: \["app-v\*"\]$/m, "it does not run on app-v* tags only");
  assert.doesNotMatch(code, /contents: write/, "it can write to the repository");
  assert.doesNotMatch(code, /allowProvisioningUpdates/, "it lets Xcode create certificates or profiles");
  assert.doesNotMatch(code, /\bcache(-[\w-]+)?: /, "it restores a cache into a job that signs");
  for (const uses of code.matchAll(/uses: (\S+)/g)) assert.match(uses[1]!, /@[0-9a-f]{40}$/, `${uses[1]} is not pinned to a commit`);

  const secret = all.findIndex((s) => /\$\{\{\s*secrets\./.test(s));
  const tests = all.findIndex((s) => /^\s+flutter analyze$/m.test(s) && /^\s+flutter test$/m.test(s));
  const xcode = all.findIndex((s) => /xcode-select -s "\$XCODE_APP"/.test(s) && /\[ "\$have" = "\$XCODE_BUILD" \] \|\|/.test(s));
  const build = all.findIndex((s) => /app\/tool\/testflight\.sh --ci/.test(s));
  const clean = all.findIndex((s) => /^\s*if: always\(\)$/m.test(s) && /security delete-keychain/.test(s));
  assert.notEqual(tests, -1, "it does not run flutter analyze and flutter test");
  assert.notEqual(xcode, -1, "it does not select one Xcode and stop when the image has another");
  assert.notEqual(build, -1, "it does not build with app/tool/testflight.sh --ci");
  assert.notEqual(clean, -1, "no step that always runs deletes the keychain");
  assert.ok(xcode < tests && tests < secret && secret < build && build < clean, "the steps are out of order: Xcode, tests, secrets, build, clean up");
  assert.doesNotMatch(all[tests]!, /^\s+(if|continue-on-error):/m);
  for (const gone of ['rm -f "$RUNNER_TEMP"/dist.p12', "AuthKey.p8", "VouchLocal.xcconfig", 'security list-keychains -d user -s']) {
    assert.ok(all[clean]!.includes(gone), `the clean-up step does not deal with: ${gone}`);
  }
  // A published app carries no Firebase config (see the Android test above): the job is given none and writes none.
  assert.doesNotMatch(text, /GoogleService-Info|GOOGLE_SERVICE/i, "release-ios.yml names a Firebase config");
  for (const name of ["IOS_DIST_CERT_P12_B64", "IOS_DIST_CERT_PASSWORD", "IOS_PROFILE_B64", "ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_P8_B64"]) {
    assert.match(code, new RegExp(`\\$\\{\\{ secrets\\.${name} \\}\\}`), `it does not read the secret ${name}`);
    assert.ok(readFileSync(new URL("../../docs/maintaining.md", import.meta.url), "utf8").includes(name), `docs/maintaining.md does not name ${name}`);
  }
  // A secret is handed to a step through its environment, never written into a command.
  for (const s of all) assert.doesNotMatch(s.slice(s.search(/^\s+run: /m)), /\$\{\{\s*secrets\./, "a secret is written into a script");
});
