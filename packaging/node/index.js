"use strict";

const fs = require("fs");
const path = require("path");
const childProcess = require("child_process");

const EXECUTABLE_TEMPLATES = [
  "native/sshfling-linux-account",
  "native/sshfling-unix-identity",
  "production/sshfling-login-shell",
  "production/sshfling-session",
  "scripts/create-network.sh",
  "scripts/generate-ssh-key.sh",
  "scripts/install-local.sh",
  "scripts/uninstall-local.sh",
  "ssh-client/entrypoint.sh",
  "ssh-server/entrypoint.sh",
  "ssh-server/limited-session.sh",
];

const SIGNAL_EXIT_CODES = {
  SIGHUP: 129,
  SIGINT: 130,
  SIGQUIT: 131,
  SIGTERM: 143,
};

function runtimePath() {
  return path.join(__dirname, "runtime", "sshfling.py");
}

function templateDir() {
  return path.join(__dirname, "runtime", "templates");
}

function pythonCandidates(env = process.env, platform = process.platform) {
  const candidates = [];
  const configuredPython = String(env.SSHFLING_PYTHON || "").trim();
  if (configuredPython) {
    candidates.push([configuredPython]);
  }

  if (platform === "win32") {
    candidates.push(["py", "-3"]);
    candidates.push(["python"]);
    candidates.push(["python3"]);
  } else {
    candidates.push(["python3"]);
    candidates.push(["python"]);
  }
  return candidates;
}

function normalizeTemplateModes(root = templateDir(), platform = process.platform) {
  const secretsDir = path.join(root, "secrets");
  const gitkeepPath = path.join(secretsDir, ".gitkeep");
  try {
    fs.mkdirSync(secretsDir, { recursive: true });
    if (!fs.existsSync(gitkeepPath)) {
      fs.writeFileSync(gitkeepPath, "");
    }
  } catch (error) {
    if (!["EACCES", "EPERM", "EROFS"].includes(error.code)) {
      throw error;
    }
  }

  if (platform === "win32") {
    return;
  }

  for (const relativePath of EXECUTABLE_TEMPLATES) {
    const target = path.join(root, relativePath);
    try {
      if (fs.existsSync(target)) {
        fs.chmodSync(target, 0o755);
      }
    } catch (error) {
      if (!["EACCES", "EPERM", "EROFS"].includes(error.code)) {
        throw error;
      }
    }
  }
}

function spawnPython(candidate, scriptPath, bundledTemplateDir, args, options) {
  const env = Object.assign({}, process.env, options.env || {});
  if (!String(env.SSHFLING_TEMPLATE_DIR || "").trim()) {
    env.SSHFLING_TEMPLATE_DIR = bundledTemplateDir;
  }
  if (!Object.prototype.hasOwnProperty.call(env, "PYTHONUNBUFFERED")) {
    env.PYTHONUNBUFFERED = "1";
  }

  return childProcess.spawnSync(
    candidate[0],
    candidate.slice(1).concat([scriptPath], args),
    {
      cwd: options.cwd || process.cwd(),
      env,
      stdio: options.stdio || "inherit",
      windowsHide: false,
    }
  );
}

function run(args = process.argv.slice(2), options = {}) {
  const scriptPath = options.scriptPath || runtimePath();
  const bundledTemplateDir = options.templateDir || templateDir();

  if (!fs.existsSync(scriptPath)) {
    console.error(`sshfling npm package is missing bundled CLI script: ${scriptPath}`);
    return 127;
  }
  if (!fs.existsSync(bundledTemplateDir)) {
    console.error(`sshfling npm package is missing bundled templates: ${bundledTemplateDir}`);
    return 127;
  }

  normalizeTemplateModes(bundledTemplateDir, options.platform || process.platform);

  const candidates = options.pythonCandidates || pythonCandidates(options.env || process.env, options.platform || process.platform);
  for (const candidate of candidates) {
    const result = spawnPython(candidate, scriptPath, bundledTemplateDir, args, options);
    if (result.error) {
      if (["ENOENT", "EACCES", "EPERM"].includes(result.error.code)) {
        continue;
      }
      console.error(`sshfling failed to start Python: ${result.error.message}`);
      return 127;
    }
    if (typeof result.status === "number") {
      return result.status;
    }
    if (result.signal) {
      return SIGNAL_EXIT_CODES[result.signal] || 1;
    }
    return 1;
  }

  console.error("sshfling requires Python 3 on PATH, or set SSHFLING_PYTHON to a Python 3 executable.");
  return 127;
}

module.exports = {
  run,
  pythonCandidates,
  normalizeTemplateModes,
  runtimePath,
  templateDir,
};
