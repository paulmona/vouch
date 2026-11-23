import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { test } from "node:test";

const ROOT = new URL("../../", import.meta.url);
const read = (p: string): string => readFileSync(new URL(p, ROOT), "utf8");
const BOTH = ["LICENSE", "NOTICE"];

// Apache-2.0 section 4: every copy that is handed on carries the licence and the NOTICE
// file. A release is a copy, so each thing a release publishes has to hold both.
test("each bundle script puts LICENSE and NOTICE in the bundle", (t) => {
  if (!existsSync(new URL("broker/deploy/bundle.sh", ROOT))) return t.skip("not a full checkout");
  for (const part of ["server", "broker"]) {
    // The script takes its files from the checked-out commit. bundles.test.ts builds a
    // bundle and lists it; this is the same check for a machine that cannot build one.
    const taken = read(`${part}/deploy/bundle.sh`).replace(/\\\n/g, " ").split("\n").filter((l) => /\barchive HEAD\b/.test(l)).join("\n");
    for (const f of BOTH) assert.match(taken, new RegExp(` ${f}( |$)`, "m"), `${part}/deploy/bundle.sh does not take ${f}`);
  }
});

test("the Docker image holds LICENSE and NOTICE, wherever it is built", (t) => {
  if (!existsSync(new URL(".github/workflows/", ROOT))) return t.skip("not a full checkout");
  const copies = read("server/Dockerfile").split("\n").filter((l) => l.startsWith("COPY ")).join("\n");
  for (const f of BOTH) assert.match(copies, new RegExp(`\\b${f}\\b`), `server/Dockerfile does not copy ${f}`);
  // The two files are at the top of the repository, so the build context has to be the
  // top too. A build from server/ alone cannot reach them.
  const kept = read("server/Dockerfile.dockerignore");
  for (const f of BOTH) assert.match(kept, new RegExp(`^!${f}$`, "m"), `the image's ignore file keeps ${f} out`);
  const release = read(".github/workflows/release-server.yml");
  assert.match(release, /^\s+context: \.\s*$/m, "the release builds the image from server/, without the licence");
  assert.match(release, /^\s+file: server\/Dockerfile\s*$/m);
  for (const p of [".github/workflows/ci.yml", "server/deploy/docker/README.md"]) {
    for (const line of read(p).split("\n").filter((l) => l.includes("docker build "))) {
      assert.match(line, /-f server\/Dockerfile \.(\s|`|$)/, `${p}: ${line.trim()}`);
    }
  }
});

test("the broker's wheel declares LICENSE and NOTICE, and they are the repository's own", (t) => {
  if (!existsSync(new URL("broker/pyproject.toml", ROOT))) return t.skip("not a full checkout");
  const declared = read("broker/pyproject.toml").match(/^license-files = \[(.*)\]$/m)?.[1] ?? "";
  for (const f of BOTH) {
    assert.ok(declared.includes(`"${f}"`), `broker/pyproject.toml does not list ${f} in license-files`);
    assert.equal(read(`broker/${f}`), read(f), `broker/${f} is not the repository's ${f}`);
  }
});

test("an app release publishes LICENSE and NOTICE beside the app", (t) => {
  if (!existsSync(new URL(".github/workflows/", ROOT))) return t.skip("not a full checkout");
  const create = read(".github/workflows/release-app.yml").split("\n").find((l) => l.includes("gh release create")) ?? "";
  for (const f of BOTH) assert.match(create, new RegExp(` ${f}\\b`), `the app release does not attach ${f}`);
});
