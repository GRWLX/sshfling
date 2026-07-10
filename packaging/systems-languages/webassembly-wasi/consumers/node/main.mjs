import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const [packageRoot, expected] = process.argv.slice(2);
if (!packageRoot || !expected) process.exit(1);
const api = await import(pathToFileURL(resolve(packageRoot, "host", "sshfling-wasi.mjs")));
const modulePath = join(packageRoot, "lib", "sshfling-wasi.wasm");
if (api.packageVersion !== expected || api.moduleVersion(modulePath) !== expected) {
  process.exit(1);
}
process.exit(api.run(modulePath, ["--version"]));
