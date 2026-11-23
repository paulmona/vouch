import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { test } from "node:test";

// The install guides have people put these next to the tracked deploy files.
const SECRET_FILES = ["deploy/docker/secrets.env", "deploy/docker/firebase.json", "deploy/docker/vault.env",
  "deploy/docker/.env", "deploy/prod/secrets.env"];

test("secret files the guides create are gitignored", (t) => {
  const cwd = new URL("..", import.meta.url);
  if (spawnSync("git", ["rev-parse", "--git-dir"], { cwd }).status !== 0) return t.skip("not a git checkout");
  for (const f of SECRET_FILES) {
    assert.equal(spawnSync("git", ["check-ignore", "-q", f], { cwd }).status, 0, `${f} is not ignored`);
  }
  assert.notEqual(spawnSync("git", ["check-ignore", "-q", "deploy/docker/secrets.env.example"], { cwd }).status, 0);
});

// Files nobody is told to create but that turn up next to a checkout: a Firebase key under
// the name the console downloads it as, and built apps.
test("a Firebase key under its default name and built apps are gitignored", (t) => {
  const cwd = new URL("../..", import.meta.url);
  if (spawnSync("git", ["rev-parse", "--git-dir"], { cwd }).status !== 0) return t.skip("not a git checkout");
  for (const f of ["server/example-project-firebase-adminsdk-ab1cd-0123456789.json", "example-project-firebase-adminsdk-ab1cd-0123456789.json",
    "app/app-release.apk", "app-release.aab", "app/Runner.ipa", "app/ios/Runner.xcarchive/Info.plist",
    "server/firebase.json", "app/firebase.json", "firebase.json", ".vault-creds/role_id", "role_id", "server/secret_id", "broker/deploy/tls.key"]) {
    assert.equal(spawnSync("git", ["check-ignore", "-q", f], { cwd }).status, 0, `${f} is not ignored`);
  }
});

// Names of real sites, devices and addresses from the setup this was built on do not belong
// in a public tree, app/ included.
test("no leftovers from a real setup", (t) => {
  const cwd = new URL("../..", import.meta.url);
  if (spawnSync("git", ["rev-parse", "--git-dir"], { cwd }).status !== 0) return t.skip("not a git checkout");
  // The second is matched as a word of its own: getSystemService is not a leftover.
  const words = ["PRE" + "STO", "(^|[^a-z])et" + "sy([^a-z]|$)", "Ep" + "cor", "Jane ?App", "S2" + "4 Ultra", "SM-S9" + "28", "private re" + "po", "10\\.0\\.0\\.48"];
  const r = spawnSync("git", ["grep", "-nIiE", words.join("|")], { cwd, encoding: "utf8" });
  assert.equal(r.stdout, "", "found:\n" + r.stdout);
});

// Comments and test names say what is checked, not which private review asked for it, and
// example names and phone numbers are plainly examples (555-01xx). The whole tree is
// searched. The one file left out is the app's own test of the same rule, whose name has
// to say what it forbids.
test("no citations of a private review and no real-looking phone numbers anywhere in the tree", (t) => {
  const cwd = new URL("../..", import.meta.url);
  if (spawnSync("git", ["rev-parse", "--git-dir"], { cwd }).status !== 0) return t.skip("not a git checkout");
  const words = ["(second|third|fourth|security) rev" + "iew", "in the rev" + "iew", "rev" + "iew [ABN]-?[0-9]", "round[- ](two|three|[0-9]) find" + "ing",
    "find" + "ing [ABN]-?[0-9]", "\\b[AB][0-9]{1,2} closed", "\\bMa" + "tt\\b", "\\+?1?[ (]*70" + "5[ )-]*555",
    "\\bro" + "und[- ](one|two|three|four|five|six|[0-9]+)\\b", "(first|second|third|fourth|fifth)[- ]ro" + "und\\b", "(after|before)-publ" + "ishing"];
  const r = spawnSync("git", ["grep", "-nIiE", words.join("|"), "--", ".", ":!app/test/hygiene_test.dart", ":!*lock*"], { cwd, encoding: "utf8" });
  assert.equal(r.stdout, "", "found:\n" + r.stdout);
});
