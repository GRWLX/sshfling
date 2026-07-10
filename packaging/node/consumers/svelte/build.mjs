import { mkdir, readFile, writeFile } from "node:fs/promises";
import { compile } from "svelte/compiler";

const filename = new URL("./src/Status.svelte", import.meta.url);
const source = await readFile(filename, "utf8");
const result = compile(source, {
  filename: filename.pathname,
  generate: "server",
  dev: false,
});

if (result.warnings.length > 0) {
  throw new Error(result.warnings.map((warning) => warning.message).join("\n"));
}

await mkdir(new URL("./build/", import.meta.url), { recursive: true });
await writeFile(new URL("./build/Status.svelte.js", import.meta.url), result.js.code);
