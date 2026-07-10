#!/usr/bin/env node
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { run } from "../host/sshfling-wasi.mjs";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
process.exit(run(join(root, "lib", "sshfling-wasi.wasm"), process.argv.slice(2)));
