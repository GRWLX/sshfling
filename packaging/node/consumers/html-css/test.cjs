"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");

const html = fs.readFileSync(new URL("./dist/index.html", `file://${__dirname}/`), "utf8");

assert.match(html, /data-runtime="static"/);
assert.match(html, /data-sshfling-ready="true"/);
assert.match(html, /does not initiate or manage SSH access/);
assert.doesNotMatch(html, /<script/i);
console.log("HTML/CSS build-time consumer verified the SSHFling Node API.");
