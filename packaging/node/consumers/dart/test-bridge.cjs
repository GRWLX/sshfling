"use strict";

const assert = require("node:assert/strict");
const childProcess = require("node:child_process");
const path = require("node:path");

const result = childProcess.spawnSync(process.execPath, [path.join(__dirname, "bridge.cjs")], {
  encoding: "utf8",
});
assert.equal(result.status, 0, result.stderr);
assert.equal(JSON.parse(result.stdout).runtime, "node");
assert.equal(JSON.parse(result.stdout).status, 0);
assert.equal(JSON.parse(result.stdout).templatesAvailable, true);
console.log("Dart Node bridge verified the SSHFling npm API.");
