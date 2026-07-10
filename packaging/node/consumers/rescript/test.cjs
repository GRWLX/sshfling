"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const consumer = require("./src/Main.js");

assert.equal(consumer.status, 0);
assert.ok(fs.existsSync(consumer.templates));
console.log("ReScript consumer verified the SSHFling Node API.");
