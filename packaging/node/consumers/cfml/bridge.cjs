"use strict";

const fs = require("node:fs");
const sshfling = require("sshfling");

const status = sshfling.run(["--version"], { stdio: "pipe" });
const templatesAvailable = fs.existsSync(sshfling.templateDir());

process.stdout.write(`${JSON.stringify({ runtime: "node", status, templatesAvailable })}\n`);
if (status !== 0 || !templatesAvailable) {
  process.exitCode = 1;
}
