import assert from "node:assert/strict";
import { existsSync } from "node:fs";
import { main, templatePath } from "./output/Main/index.js";

assert.equal(main, 0);
assert.ok(existsSync(templatePath));
console.log("PureScript FFI consumer verified the SSHFling Node API.");
