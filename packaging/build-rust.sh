#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=packaging/version.sh
source "$repo_root/packaging/version.sh"
version="$(assert_sshfling_version_matches_source "${SSHFLING_VERSION:-}" "$repo_root")"

cargo_cmd="${CARGO:-cargo}"
if ! command -v "$cargo_cmd" >/dev/null 2>&1; then
  echo "Cargo and Rust 1.70 or newer are required to build the SSHFling crate." >&2
  echo "Install Rust, or set CARGO to a Cargo executable." >&2
  exit 127
fi
if ! "$cargo_cmd" fmt --version >/dev/null 2>&1; then
  echo "rustfmt is required to validate the SSHFling crate." >&2
  exit 127
fi
if ! "$cargo_cmd" clippy --version >/dev/null 2>&1; then
  echo "Clippy is required to validate the SSHFling crate." >&2
  exit 127
fi

dist_dir="$repo_root/dist"
build_root="$repo_root/build/rust"
project_dir="$build_root/project"
validation_dir="$build_root/validation"
cargo_target_dir="$build_root/target"
crate_path="$dist_dir/sshfling-cli-$version.crate"

export LC_ALL=C
export TZ=UTC
export CARGO_HOME="$build_root/cargo-home"
export CARGO_TARGET_DIR="$cargo_target_dir"
export CARGO_NET_OFFLINE=true
umask 022

copy_rust_project() {
  rm -rf "$project_dir"
  install -d "$project_dir"
  cp -R "$repo_root/packaging/rust/." "$project_dir/"
  install -m 0644 "$repo_root/LICENSE" "$project_dir/LICENSE"
  install -m 0644 "$repo_root/README.md" "$project_dir/README.md"
  install -d "$project_dir/runtime"
  install -m 0755 "$repo_root/bin/sshfling" "$project_dir/runtime/sshfling.py"

  # shellcheck source=packaging/copy-templates.sh
  source "$repo_root/packaging/copy-templates.sh"
  copy_sshfling_templates "$repo_root" "$project_dir/runtime/templates"

  sed -i "s/^version = \"0.0.0\"$/version = \"$version\"/" "$project_dir/Cargo.toml"
  grep -Fqx "version = \"$version\"" "$project_dir/Cargo.toml"
}

validate_rust_project() {
  (
    cd "$project_dir"
    "$cargo_cmd" fmt --check
    "$cargo_cmd" test --all-targets
    "$cargo_cmd" clippy --all-targets -- -D warnings
    "$cargo_cmd" package --allow-dirty
  )
  if [[ "${SSHFLING_RUST_PUBLISH_DRY_RUN:-}" == "1" ]]; then
    (
      cd "$project_dir"
      CARGO_NET_OFFLINE=false "$cargo_cmd" publish --dry-run --allow-dirty
    )
  fi
}

copy_and_validate_crate() {
  local built_crate="$cargo_target_dir/package/sshfling-cli-$version.crate"
  local prefix="sshfling-cli-$version"

  if [[ ! -s "$built_crate" ]]; then
    echo "Cargo package was not created: $built_crate" >&2
    exit 1
  fi
  cp "$built_crate" "$crate_path"

  tar -tzf "$crate_path" | grep -Fx "$prefix/Cargo.toml" >/dev/null
  tar -tzf "$crate_path" | grep -Fx "$prefix/src/lib.rs" >/dev/null
  tar -tzf "$crate_path" | grep -Fx "$prefix/src/main.rs" >/dev/null
  tar -tzf "$crate_path" | grep -Fx "$prefix/runtime/sshfling.py" >/dev/null
  tar -tzf "$crate_path" | grep -Fx "$prefix/runtime/templates/systemd/sshfling-prune.timer" >/dev/null
  tar -tzf "$crate_path" | grep -Fx "$prefix/runtime/templates/native/sshfling-linux-account" >/dev/null
  tar -tzf "$crate_path" | grep -Fx "$prefix/runtime/templates/native/sshfling-unix-identity" >/dev/null
  tar -tzf "$crate_path" | grep -Fx "$prefix/runtime/templates/production/sshfling-login-shell" >/dev/null
  tar -tzf "$crate_path" | grep -Fx "$prefix/runtime/templates/secrets/.gitkeep" >/dev/null
}

validate_crate_install() {
  local extracted_dir="$validation_dir/extracted"
  local install_root="$validation_dir/install"
  local smoke_project="$validation_dir/smoke-project"
  local prefix="sshfling-cli-$version"

  install -d "$extracted_dir" "$install_root"
  tar -xzf "$crate_path" -C "$extracted_dir"
  "$cargo_cmd" install \
    --path "$extracted_dir/$prefix" \
    --root "$install_root" \
    --offline \
    --locked

  test -x "$install_root/bin/sshfling"
  "$install_root/bin/sshfling" --version | grep -Fx "sshfling $version" >/dev/null
  "$install_root/bin/sshfling" --project-dir "$smoke_project" doctor >/dev/null
  "$install_root/bin/sshfling" init "$smoke_project" --force --session-seconds 60 >/dev/null
  test -x "$smoke_project/scripts/install-local.sh"
  test -x "$smoke_project/scripts/uninstall-local.sh"
  test -x "$smoke_project/native/sshfling-linux-account"
  test -x "$smoke_project/native/sshfling-unix-identity"
  test -x "$smoke_project/production/sshfling-login-shell"
  test -x "$smoke_project/production/sshfling-session"
  test -f "$smoke_project/secrets/.gitkeep"

  "$cargo_cmd" uninstall --root "$install_root" sshfling-cli
  test ! -e "$install_root/bin/sshfling"
  test ! -e "$install_root/bin/sshfling.exe"
}

rm -rf "$build_root"
install -d "$build_root" "$validation_dir" "$dist_dir"
rm -f "$crate_path"

copy_rust_project
validate_rust_project
copy_and_validate_crate
validate_crate_install

printf '%s\n' "$crate_path"
