"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const sshfling = require("sshfling");
const { Elm } = require("./build/elm.js");

const app = Elm.Main.init({ flags: { arguments: ["--version"] } });
const timeout = setTimeout(() => {
  throw new Error("Elm worker did not complete the Node port round trip.");
}, 5000);

app.ports.requestSshfling.subscribe((args) => {
  assert.deepEqual(args, ["--version"]);
  const exitCode = sshfling.run(args, { stdio: "pipe" });
  assert.ok(fs.existsSync(sshfling.templateDir()));
  app.ports.sshflingResult.send(exitCode);
});

app.ports.completed.subscribe((exitCode) => {
  clearTimeout(timeout);
  assert.equal(exitCode, 0);
  console.log("Elm worker verified the SSHFling Node API through server-side ports.");
});
