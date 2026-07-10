#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=packaging/version.sh
source "$repo_root/packaging/version.sh"
version="$(assert_sshfling_version_matches_source "${SSHFLING_VERSION:-}" "$repo_root")"

go_cmd="${GO:-go}"
if ! command -v "$go_cmd" >/dev/null 2>&1; then
  echo "Go 1.22 or newer is required to build the SSHFling Go module." >&2
  echo "Install Go, or set GO to a Go executable." >&2
  exit 127
fi
if ! command -v zip >/dev/null 2>&1 || ! command -v unzip >/dev/null 2>&1; then
  echo "zip and unzip are required to build the SSHFling Go module archive." >&2
  exit 127
fi

dist_dir="$repo_root/dist"
build_root="$repo_root/build/go"
project_name="sshfling-go-$version"
project_dir="$build_root/$project_name"
validation_dir="$build_root/validation"
archive_path="$dist_dir/$project_name.zip"

export LC_ALL=C
export TZ=UTC
export CGO_ENABLED=0
export GOFLAGS=-mod=readonly
export GOCACHE="$build_root/go-cache"
export GOMODCACHE="$build_root/go-mod-cache"
umask 022

copy_go_project() {
  rm -rf "$project_dir"
  install -d "$project_dir"
  cp -R "$repo_root/packaging/go/." "$project_dir/"
  install -m 0644 "$repo_root/LICENSE" "$project_dir/LICENSE"
  install -m 0644 "$repo_root/README.md" "$project_dir/README.md"
  install -d "$project_dir/runtime"
  install -m 0755 "$repo_root/bin/sshfling" "$project_dir/runtime/sshfling.py"

  # shellcheck source=packaging/copy-templates.sh
  source "$repo_root/packaging/copy-templates.sh"
  copy_sshfling_templates "$repo_root" "$project_dir/runtime/templates"

  sed -i "s/const Version = \"0.0.0\"/const Version = \"$version\"/" "$project_dir/sshfling.go"
  grep -Fqx "const Version = \"$version\"" "$project_dir/sshfling.go"
}

validate_go_sources() {
  local unformatted

  unformatted="$(find "$repo_root/packaging/go" -type f -name '*.go' -print0 | xargs -0 gofmt -l)"
  if [[ -n "$unformatted" ]]; then
    echo "Go sources require gofmt:" >&2
    printf '%s\n' "$unformatted" >&2
    exit 1
  fi

  (
    cd "$project_dir"
    "$go_cmd" test ./...
    "$go_cmd" vet ./...
  )
}

build_archive() {
  rm -f "$archive_path"
  (
    cd "$build_root"
    zip -X -q -r "$archive_path" "$project_name" \
      -x "$project_name/.git/*"
  )

  unzip -Z1 "$archive_path" | grep -Fx "$project_name/go.mod" >/dev/null
  unzip -Z1 "$archive_path" | grep -Fx "$project_name/sshfling.go" >/dev/null
  unzip -Z1 "$archive_path" | grep -Fx "$project_name/cmd/sshfling/main.go" >/dev/null
  unzip -Z1 "$archive_path" | grep -Fx "$project_name/runtime/sshfling.py" >/dev/null
  unzip -Z1 "$archive_path" | grep -Fx "$project_name/runtime/templates/systemd/sshfling-prune.timer" >/dev/null
  unzip -Z1 "$archive_path" | grep -Fx "$project_name/runtime/templates/native/sshfling-linux-account" >/dev/null
  unzip -Z1 "$archive_path" | grep -Fx "$project_name/runtime/templates/native/sshfling-unix-identity" >/dev/null
  unzip -Z1 "$archive_path" | grep -Fx "$project_name/runtime/templates/production/sshfling-login-shell" >/dev/null
  unzip -Z1 "$archive_path" | grep -Fx "$project_name/runtime/templates/secrets/.gitkeep" >/dev/null
}

validate_archive_install() {
  local extracted_root="$validation_dir/extracted"
  local install_bin="$validation_dir/bin"
  local smoke_project="$validation_dir/smoke-project"

  install -d "$extracted_root" "$install_bin"
  unzip -q "$archive_path" -d "$extracted_root"
  (
    cd "$extracted_root/$project_name"
    GOBIN="$install_bin" "$go_cmd" install ./cmd/sshfling
  )

  test -x "$install_bin/sshfling"
  "$install_bin/sshfling" --version | grep -Fx "sshfling $version" >/dev/null
  "$install_bin/sshfling" --project-dir "$smoke_project" doctor >/dev/null
  "$install_bin/sshfling" init "$smoke_project" --force --session-seconds 60 >/dev/null
  test -x "$smoke_project/scripts/install-local.sh"
  test -x "$smoke_project/scripts/uninstall-local.sh"
  test -x "$smoke_project/native/sshfling-linux-account"
  test -x "$smoke_project/native/sshfling-unix-identity"
  test -x "$smoke_project/production/sshfling-login-shell"
  test -x "$smoke_project/production/sshfling-session"
  test -f "$smoke_project/secrets/.gitkeep"

  rm -f "$install_bin/sshfling" "$install_bin/sshfling.exe"
  test ! -e "$install_bin/sshfling"
  test ! -e "$install_bin/sshfling.exe"
}

rm -rf "$build_root"
install -d "$build_root" "$validation_dir" "$dist_dir"

copy_go_project
validate_go_sources
build_archive
validate_archive_install

printf '%s\n' "$archive_path"
