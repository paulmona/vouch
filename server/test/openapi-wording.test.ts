import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

const SPEC = new URL("../../api/openapi.yaml", import.meta.url);

// The check-in description must not promise more than a check-in shows: on
// Android the answer can wait until the app is next opened.
test("the check-in description does not overstate what a check-in proves", () => {
  const spec = readFileSync(SPEC, "utf8");
  const start = spec.indexOf("operationId: checkIn");
  assert.ok(start > 0, "checkIn not found");
  const op = spec.slice(start, spec.indexOf("requestBody:", start));
  assert.ok(!op.includes("Proves the whole path works"), "says a check-in proves the whole path");
  assert.ok(op.includes("On Android the answer can wait until the app is next opened"), "leaves out the Android delay");
});
