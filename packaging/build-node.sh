#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=packaging/version.sh
source "$repo_root/packaging/version.sh"
version="$(assert_sshfling_version_matches_source "${SSHFLING_VERSION:-}" "$repo_root")"

node_cmd="${NODE:-node}"
npm_cmd="${NPM:-npm}"
if ! command -v "$node_cmd" >/dev/null 2>&1; then
  echo "Node.js 18 or newer is required to build the SSHFling npm package." >&2
  echo "Install Node.js and npm, or set NODE to a Node.js executable." >&2
  exit 127
fi
if ! command -v "$npm_cmd" >/dev/null 2>&1; then
  echo "npm is required to build the SSHFling npm package." >&2
  echo "Install npm, or set NPM to an npm executable." >&2
  exit 127
fi

dist_dir="$repo_root/dist"
build_root="$repo_root/build/node"
package_dir="$build_root/package"
validation_dir="$build_root/validation"
package_path="$dist_dir/sshfling-$version.tgz"
typescript_version="${SSHFLING_TYPESCRIPT_VERSION:-5.9.3}"

export LC_ALL=C
export TZ=UTC
export npm_config_audit=false
export npm_config_fund=false
export npm_config_update_notifier=false
umask 022

copy_node_project() {
  rm -rf "$package_dir"
  install -d "$package_dir/bin" "$package_dir/runtime"
  install -m 0644 "$repo_root/packaging/node/package.json" "$package_dir/package.json"
  install -m 0644 "$repo_root/packaging/node/index.js" "$package_dir/index.js"
  install -m 0644 "$repo_root/packaging/node/index.d.ts" "$package_dir/index.d.ts"
  install -m 0644 "$repo_root/LICENSE" "$package_dir/LICENSE"
  install -m 0644 "$repo_root/README.md" "$package_dir/README.md"
  install -m 0755 "$repo_root/packaging/node/bin/sshfling.js" "$package_dir/bin/sshfling.js"
  install -m 0644 "$repo_root/bin/sshfling" "$package_dir/runtime/sshfling.py"

  # shellcheck source=packaging/copy-templates.sh
  source "$repo_root/packaging/copy-templates.sh"
  copy_sshfling_templates "$repo_root" "$package_dir/runtime/templates"
}

write_package_version() {
  "$node_cmd" -e '
const fs = require("fs");
const packagePath = process.argv[1];
const version = process.argv[2];
const data = JSON.parse(fs.readFileSync(packagePath, "utf8"));
data.version = version;
fs.writeFileSync(packagePath, `${JSON.stringify(data, null, 2)}\n`);
' "$package_dir/package.json" "$version"
}

validate_node_sources() {
  "$node_cmd" --check "$repo_root/packaging/node/index.js"
  "$node_cmd" --check "$repo_root/packaging/node/bin/sshfling.js"
}

validate_package_contents() {
  tar -tzf "$package_path" | grep -Fx "package/runtime/sshfling.py" >/dev/null
  tar -tzf "$package_path" | grep -Fx "package/runtime/templates/systemd/sshfling-prune.service" >/dev/null
  tar -tzf "$package_path" | grep -Fx "package/runtime/templates/systemd/sshfling-prune.timer" >/dev/null
  tar -tzf "$package_path" | grep -Fx "package/runtime/templates/native/sshfling-linux-account" >/dev/null
  tar -tzf "$package_path" | grep -Fx "package/runtime/templates/native/sshfling-unix-identity" >/dev/null
  tar -tzf "$package_path" | grep -Fx "package/runtime/templates/secrets/.gitkeep" >/dev/null
  tar -tzf "$package_path" | grep -Fx "package/bin/sshfling.js" >/dev/null
  tar -tzf "$package_path" | grep -Fx "package/index.d.ts" >/dev/null
  tar -tzf "$package_path" | grep -Fx "package/LICENSE" >/dev/null
  tar -tzf "$package_path" | grep -Fx "package/README.md" >/dev/null
}

validate_installed_package() {
  local app_dir="$validation_dir/app"
  local smoke_project="$validation_dir/smoke-project"
  local bin_path="$app_dir/node_modules/.bin/sshfling"

  rm -rf "$validation_dir"
  install -d "$app_dir"
  "$npm_cmd" install --prefix "$app_dir" "$package_path" "typescript@$typescript_version" >/dev/null

  test -s "$app_dir/package-lock.json"
  test -x "$bin_path"
  "$bin_path" --version | grep -Fx "sshfling $version" >/dev/null
  "$bin_path" --project-dir "$smoke_project" doctor >/dev/null
  "$bin_path" init "$smoke_project" --force --session-seconds 60 >/dev/null
  test -x "$smoke_project/scripts/install-local.sh"
  test -x "$smoke_project/scripts/uninstall-local.sh"
  test -x "$smoke_project/native/sshfling-linux-account"
  test -x "$smoke_project/native/sshfling-unix-identity"
  test -x "$smoke_project/production/sshfling-session"
  test -f "$smoke_project/secrets/.gitkeep"

  (
    cd "$app_dir"
    "$node_cmd" -e 'const api = require("sshfling"); if (typeof api.run !== "function" || typeof api.templateDir !== "function") throw new Error("CommonJS API shape mismatch"); if (api.run(["--version"], {stdio: "pipe"}) !== 0) throw new Error("CommonJS library run failed");'
    "$node_cmd" --input-type=module -e 'const mod = await import("sshfling"); const api = mod.default || mod; if (typeof api.run !== "function" || typeof api.templateDir !== "function") throw new Error("ESM import API shape mismatch"); if (api.run(["--version"], {stdio: "pipe"}) !== 0) throw new Error("ESM library run failed");'
  )

  install -m 0644 "$repo_root/packaging/node/consumers/typescript.ts" "$app_dir/typescript.ts"
  "$app_dir/node_modules/.bin/tsc" \
    --strict \
    --noEmit \
    --module Node16 \
    --moduleResolution Node16 \
    --target ES2022 \
    "$app_dir/typescript.ts"

  "$npm_cmd" uninstall --prefix "$app_dir" sshfling >/dev/null
  test ! -e "$bin_path"
}

rm -rf "$build_root"
install -d "$build_root" "$dist_dir"
rm -f "$package_path"

validate_node_sources
copy_node_project
write_package_version

"$npm_cmd" pack "$package_dir" --pack-destination "$dist_dir" --ignore-scripts >/dev/null
if [[ ! -s "$package_path" ]]; then
  echo "npm package was not created: $package_path" >&2
  exit 1
fi

validate_package_contents
validate_installed_package

printf '%s\n' "$package_path"
