import assert from "node:assert/strict";
import { render } from "svelte/server";
import Status from "../build/Status.svelte.js";

const { body } = render(Status);

assert.match(body, /data-runtime="node"/);
assert.match(body, /data-sshfling-ready="true"/);
assert.doesNotMatch(body, /<script/i);
console.log("Svelte SSR consumer verified the SSHFling Node API.");
