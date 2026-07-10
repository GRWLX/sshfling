import assert from "node:assert/strict";
import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { StatusPage } from "../build/StatusPage.mjs";

const html = renderToStaticMarkup(React.createElement(StatusPage));

assert.match(html, /data-runtime="node"/);
assert.match(html, /data-sshfling-ready="true"/);
assert.doesNotMatch(html, /<script/i);
console.log("React SSR consumer verified the SSHFling Node API.");
