import "zone.js/node";
import "@angular/compiler";

import assert from "node:assert/strict";
import { existsSync } from "node:fs";
import { Component, enableProdMode } from "@angular/core";
import { bootstrapApplication } from "@angular/platform-browser";
import { renderApplication } from "@angular/platform-server";
import sshfling from "sshfling";

enableProdMode();

@Component({
  selector: "sshfling-status",
  standalone: true,
  template: `
    <main data-runtime="node" [attr.data-sshfling-ready]="ready">
      <h1>SSHFling server status</h1>
      <p>{{ ready ? "The Node library and bundled templates are available." : "The server-side check failed." }}</p>
    </main>
  `,
})
class SshflingStatusComponent {
  // Component construction happens in Angular's server renderer.
  readonly ready = sshfling.run(["--version"], { stdio: "pipe" }) === 0
    && existsSync(sshfling.templateDir());
}

const html = await renderApplication(
  () => bootstrapApplication(SshflingStatusComponent),
  { document: "<!doctype html><html><body><sshfling-status></sshfling-status></body></html>" },
);

assert.match(html, /data-runtime="node"/);
assert.match(html, /data-sshfling-ready="true"/);
assert.doesNotMatch(html, /<script/i);
console.log("Angular SSR consumer verified the SSHFling Node API.");
