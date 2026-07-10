#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
consumer_root="$repo_root/packaging/node/consumers"
node_cmd="${NODE:-node}"
npm_cmd="${NPM:-npm}"

all_consumers=(
  react
  vue
  svelte
  angular
  elm
  purescript
  rescript
  html-css
  cfml
  dart
  hack
)

if (($# > 0)); then
  selected_consumers=("$@")
else
  selected_consumers=("${all_consumers[@]}")
fi

is_known_consumer() {
  local requested="$1"
  local known
  for known in "${all_consumers[@]}"; do
    if [[ "$requested" == "$known" ]]; then
      return 0
    fi
  done
  return 1
}

for consumer in "${selected_consumers[@]}"; do
  if ! is_known_consumer "$consumer"; then
    echo "Unknown web-language consumer: $consumer" >&2
    echo "Choose from: ${all_consumers[*]}" >&2
    exit 2
  fi
done

if ! command -v "$node_cmd" >/dev/null 2>&1; then
  echo "Node.js 18 or newer is required for web-language consumers." >&2
  exit 127
fi
if ! command -v "$npm_cmd" >/dev/null 2>&1; then
  echo "npm is required for web-language consumers." >&2
  exit 127
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "Python 3 is required by the SSHFling npm package runtime." >&2
  exit 127
fi

node_major="$($node_cmd -p 'Number(process.versions.node.split(".")[0])')"
if ((node_major < 18)); then
  echo "Node.js 18 or newer is required; found $($node_cmd --version)." >&2
  exit 2
fi

if [[ -n "${SSHFLING_NPM_PACKAGE:-}" ]]; then
  package_path="$SSHFLING_NPM_PACKAGE"
else
  # shellcheck disable=SC1091
  source "$repo_root/packaging/version.sh"
  version="$(sshfling_source_version "$repo_root")"
  package_path="$repo_root/dist/sshfling-$version.tgz"
fi

if [[ ! -s "$package_path" ]]; then
  echo "Packed SSHFling npm artifact not found: $package_path" >&2
  echo "Set SSHFLING_NPM_PACKAGE to an existing package tarball." >&2
  echo "This focused validator intentionally does not run a repository package build." >&2
  exit 2
fi
package_path="$(realpath "$package_path")"
tar -tzf "$package_path" | grep -Fx "package/index.js" >/dev/null
tar -tzf "$package_path" | grep -Fx "package/index.d.ts" >/dev/null
tar -tzf "$package_path" | grep -Fx "package/runtime/sshfling.py" >/dev/null

work_root="$(mktemp -d "${TMPDIR:-/tmp}/sshfling-web-consumers.XXXXXX")"
trap 'rm -rf "$work_root"' EXIT

export LC_ALL=C
export TZ=UTC
export NODE="$node_cmd"
export XDG_CACHE_HOME="$work_root/xdg-cache"
export npm_config_audit=false
export npm_config_fund=false
export npm_config_progress=false
export npm_config_update_notifier=false

install_consumer() {
  local consumer="$1"
  local app_dir="$2"

  mkdir -p "$app_dir"
  cp -R "$consumer_root/$consumer/." "$app_dir/"
  # shellcheck disable=SC2016
  "$node_cmd" -e '
const fs = require("fs");
const manifestPath = process.argv[1];
const packagePath = process.argv[2];
const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
manifest.dependencies.sshfling = `file:${packagePath}`;
fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
' "$app_dir/package.json" "$package_path"

  (
    cd "$app_dir"
    "$npm_cmd" install --no-package-lock --loglevel=error
  )
}

validate_consumer() (
  set -e
  local consumer="$1"
  local app_dir="$work_root/$consumer"
  local cache_dir="$work_root/npm-cache"
  export ELM_HOME="$work_root/elm-home"
  export npm_config_cache="$cache_dir"

  install_consumer "$consumer" "$app_dir"
  cd "$app_dir"

  case "$consumer" in
    cfml)
      "$npm_cmd" run test:node
      if ! command -v box >/dev/null 2>&1; then
        echo "CFML validation is GATED: CommandBox ('box') is not installed." >&2
        exit 42
      fi
      "$npm_cmd" run test:cfml
      ;;
    dart)
      "$npm_cmd" run test:node
      if ! command -v dart >/dev/null 2>&1; then
        echo "Dart validation is GATED: the 'dart' toolchain is not installed." >&2
        exit 42
      fi
      "$npm_cmd" run test:dart
      ;;
    hack)
      "$npm_cmd" run test:node
      if ! command -v hhvm >/dev/null 2>&1; then
        echo "Hack validation is GATED: the 'hhvm' toolchain is not installed." >&2
        exit 42
      fi
      "$npm_cmd" run test:hack
      ;;
    *)
      "$npm_cmd" test
      ;;
  esac
)

passed=()
gated=()
failed=()

for consumer in "${selected_consumers[@]}"; do
  printf '[RUN] %s\n' "$consumer"
  set +e
  validate_consumer "$consumer"
  result=$?
  set -e

  # Delete only this script's isolated install and cache before the next consumer.
  rm -rf "${work_root:?}/$consumer" "$work_root/npm-cache"

  case "$result" in
    0)
      passed+=("$consumer")
      printf '[PASS] %s\n' "$consumer"
      ;;
    42)
      gated+=("$consumer")
      printf '[GATED] %s (required external toolchain unavailable)\n' "$consumer"
      ;;
    *)
      failed+=("$consumer")
      printf '[FAIL] %s (exit %s)\n' "$consumer" "$result" >&2
      ;;
  esac
done

printf 'Consumer summary: %s passed, %s gated, %s failed.\n' \
  "${#passed[@]}" "${#gated[@]}" "${#failed[@]}"

if ((${#gated[@]} > 0)); then
  printf 'Gated (not passed): %s\n' "${gated[*]}" >&2
fi
if ((${#failed[@]} > 0)); then
  printf 'Failed: %s\n' "${failed[*]}" >&2
fi

# Missing external language runtimes are deliberately fail-closed. A caller
# must not turn a partial Node-bridge check into a language support PASS claim.
if ((${#gated[@]} > 0 || ${#failed[@]} > 0)); then
  exit 1
fi
