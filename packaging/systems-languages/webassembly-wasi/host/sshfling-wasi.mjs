import { constants as fsConstants, accessSync, readFileSync } from "node:fs";
import { constants as osConstants } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import { WASI } from "node:wasi";

export const packageVersion = "0.0.0";

const packageRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const decoder = new TextDecoder();

function readCString(memory, pointer) {
  const bytes = new Uint8Array(memory.buffer);
  let end = pointer;
  while (end < bytes.length && bytes[end] !== 0) end += 1;
  if (end === bytes.length) throw new Error("unterminated guest string");
  return decoder.decode(bytes.subarray(pointer, end));
}

function guestArguments(memory, count, pointer) {
  const view = new DataView(memory.buffer);
  const values = [];
  for (let index = 0; index < count; index += 1) {
    values.push(readCString(memory, view.getUint32(pointer + (index * 4), true)));
  }
  return values;
}

function runtimeLayout(environment) {
  const root = environment.SSHFLING_RUNTIME_DIR || join(packageRoot, "runtime");
  return { root, script: join(root, "sshfling.py"), templates: join(root, "templates") };
}

function usableRuntime(layout) {
  try {
    accessSync(layout.script, fsConstants.R_OK);
    accessSync(layout.templates, fsConstants.R_OK | fsConstants.X_OK);
    return true;
  } catch {
    return false;
  }
}

function selectPython(environment) {
  const candidates = environment.SSHFLING_PYTHON
    ? [environment.SSHFLING_PYTHON]
    : ["python3", "python"];
  for (const candidate of candidates) {
    const probe = spawnSync(candidate, ["-c", "import sys; raise SystemExit(sys.version_info[0] != 3)"], {
      env: environment,
      stdio: "ignore",
    });
    if (probe.status === 0) return candidate;
  }
  return null;
}

function signaledStatus(signal) {
  const number = osConstants.signals[signal];
  return Number.isInteger(number) ? 128 + number : 1;
}

function instantiate(modulePath, arguments_, environment, invokeHost) {
  const wasi = new WASI({
    version: "preview1",
    args: [modulePath, ...arguments_],
    env: environment,
    preopens: {},
    returnOnExit: true,
  });
  let instance;
  const imports = {
    wasi_snapshot_preview1: wasi.wasiImport,
    "sshfling:launcher": {
      run(count, pointer) {
        return invokeHost(guestArguments(instance.exports.memory, count, pointer));
      },
    },
  };
  const module = new WebAssembly.Module(readFileSync(modulePath));
  instance = new WebAssembly.Instance(module, imports);
  return { instance, wasi };
}

export function moduleVersion(modulePath, environment = process.env) {
  const { instance } = instantiate(modulePath, [], { ...environment }, () => 0);
  const pointer = instance.exports.sshfling_wasi_version();
  return readCString(instance.exports.memory, pointer);
}

export function run(modulePath, arguments_, environment = process.env) {
  const childEnvironment = { ...environment };
  const layout = runtimeLayout(childEnvironment);
  if (!usableRuntime(layout)) {
    console.error(`sshfling: bundled runtime is unavailable under ${layout.root}`);
    return 127;
  }
  const python = selectPython(childEnvironment);
  if (!python) {
    console.error("sshfling: Python 3 is required; set SSHFLING_PYTHON to its executable");
    return 127;
  }
  if (!childEnvironment.SSHFLING_TEMPLATE_DIR) {
    childEnvironment.SSHFLING_TEMPLATE_DIR = layout.templates;
  }
  if (!childEnvironment.PYTHONUNBUFFERED) childEnvironment.PYTHONUNBUFFERED = "1";

  const { instance, wasi } = instantiate(modulePath, arguments_, childEnvironment, (guestArgs) => {
    const child = spawnSync(python, [layout.script, ...guestArgs], {
      env: childEnvironment,
      stdio: "inherit",
    });
    if (Number.isInteger(child.status)) return child.status;
    if (child.signal) return signaledStatus(child.signal);
    return child.error?.code === "ENOENT" ? 127 : 126;
  });
  return wasi.start(instance);
}
