import { existsSync } from "node:fs";
import React from "react";
import sshfling from "sshfling";

// This component is rendered by React on Node. It is not shipped to a browser.
export function StatusPage() {
  const exitCode = sshfling.run(["--version"], { stdio: "pipe" });
  const templatesAvailable = existsSync(sshfling.templateDir());
  const ready = exitCode === 0 && templatesAvailable;

  return (
    <main data-runtime="node" data-sshfling-ready={String(ready)}>
      <h1>SSHFling server status</h1>
      <p>{ready ? "The Node library and bundled templates are available." : "The server-side check failed."}</p>
    </main>
  );
}
