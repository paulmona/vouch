import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { test } from "node:test";

const ROOT = new URL("../../", import.meta.url);
const CONFIG = new URL(".github/dependabot.yml", ROOT);

// Where a pinned dependency lives, and what watches it. SECURITY.md tells an installer
// which dependencies nobody is watching, so the two have to say the same thing.
const WATCHED: [ecosystem: string, directory: string, pins: string][] = [
  ["github-actions", "/", ".github/workflows/ci.yml"],
  ["npm", "/server", "server/package-lock.json"],
  ["pub", "/app", "app/pubspec.yaml"],
  ["uv", "/broker", "broker/uv.lock"],
  ["docker", "/server", "server/Dockerfile"],
  ["docker-compose", "/server/deploy/docker", "server/deploy/docker/compose.yaml"],
  ["gradle", "/app/android", "app/android/settings.gradle.kts"],
];

test("automatic update checks cover every pinned dependency except the one SECURITY.md names", (t) => {
  if (!existsSync(CONFIG)) return t.skip("not a full checkout");
  const entries = readFileSync(CONFIG, "utf8").split(/^ {2}- /m).slice(1);
  const found = entries.map((e) => `${e.match(/^package-ecosystem: (\S+)/)?.[1]} ${e.match(/^ {4}directory: (\S+)/m)?.[1]}`);
  for (const [ecosystem, directory, pins] of WATCHED) {
    assert.ok(existsSync(new URL(pins, ROOT)), `${pins} is gone: the list in this test is out of date`);
    assert.ok(found.includes(`${ecosystem} ${directory}`), `nothing checks ${pins} (${ecosystem} in ${directory})`);
  }
  for (const e of entries) {
    assert.match(e, /^ {6}interval: weekly$/m);
    assert.match(e, /^ {6}default-days: 14$/m, "an update must wait until the version is two weeks old");
  }

  const text = readFileSync(new URL("SECURITY.md", ROOT), "utf8").replace(/\s+/g, " ");
  const limits = text.slice(text.indexOf("## Known limits"));
  const start = limits.indexOf("is updated by hand");
  assert.notEqual(start, -1, "Known limits does not say what is updated by hand");
  const limit = limits.slice(limits.lastIndexOf("- **", start), limits.indexOf(" - **", start));
  assert.match(limit, /Playwright version that `browser\/setup` installs/);
  assert.ok(!/do not cover the broker|Docker base images or/.test(limit), "the limit still lists dependencies that are now checked");
  assert.match(readFileSync(new URL("browser/setup", ROOT), "utf8"), /^PLAYWRIGHT_VERSION=/m, "browser/setup no longer pins Playwright: is the limit still true?");
});

// The image runs the Node that CI tests and the release bundle is built with. A new major
// arrives as one deliberate change to all three, not as an update to the image alone.
test("the Docker image's Node is not moved to a new major by an automatic update", (t) => {
  if (!existsSync(CONFIG)) return t.skip("not a full checkout");
  const docker = readFileSync(CONFIG, "utf8").split(/^ {2}- /m).slice(1).find((e) => /^package-ecosystem: docker\n {4}directory: \/server$/m.test(e));
  assert.ok(docker, "no docker entry for /server");
  assert.match(docker, /ignore:\n(?: +#.*\n)* +- dependency-name: "?node"?\n +update-types: \["version-update:semver-major"\]/);
});
