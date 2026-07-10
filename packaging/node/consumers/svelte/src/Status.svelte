<script>
  import { existsSync } from "node:fs";
  import sshfling from "sshfling";

  // This module is compiled only for Svelte's Node server renderer.
  const exitCode = sshfling.run(["--version"], { stdio: "pipe" });
  const ready = exitCode === 0 && existsSync(sshfling.templateDir());
</script>

<main data-runtime="node" data-sshfling-ready={String(ready)}>
  <h1>SSHFling server status</h1>
  <p>{ready ? "The Node library and bundled templates are available." : "The server-side check failed."}</p>
</main>
