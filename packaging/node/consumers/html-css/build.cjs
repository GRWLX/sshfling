"use strict";

const fs = require("node:fs");
const path = require("node:path");
const sshfling = require("sshfling");

const exitCode = sshfling.run(["--version"], { stdio: "pipe" });
const ready = exitCode === 0 && fs.existsSync(sshfling.templateDir());
if (!ready) {
  throw new Error("The server-side SSHFling build check failed.");
}

const outputDir = path.join(__dirname, "dist");
fs.mkdirSync(outputDir, { recursive: true });
fs.copyFileSync(path.join(__dirname, "src", "styles.css"), path.join(outputDir, "styles.css"));
fs.writeFileSync(path.join(outputDir, "index.html"), `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>SSHFling server status</title>
    <link rel="stylesheet" href="styles.css">
  </head>
  <body>
    <main data-runtime="static" data-sshfling-ready="true">
      <h1>SSHFling server status</h1>
      <p>The SSHFling package was verified during this trusted Node build.</p>
      <p>This static page does not initiate or manage SSH access.</p>
    </main>
  </body>
</html>
`);
