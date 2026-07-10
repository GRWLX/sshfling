import assert from "node:assert/strict";
import { renderToString } from "@vue/server-renderer";
import { createSSRApp } from "vue";
import { StatusApp } from "../src/status-app.mjs";

const html = await renderToString(createSSRApp(StatusApp));

assert.match(html, /data-runtime="node"/);
assert.match(html, /data-sshfling-ready="true"/);
assert.doesNotMatch(html, /<script/i);
console.log("Vue SSR consumer verified the SSHFling Node API.");
