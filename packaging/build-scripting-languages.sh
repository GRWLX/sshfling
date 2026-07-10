#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck disable=SC1091
source "$repo_root/packaging/version.sh"
version="$(assert_sshfling_version_matches_source "${SSHFLING_VERSION:-}" "$repo_root")"

# shellcheck disable=SC1091
source "$repo_root/packaging/copy-templates.sh"

build_root="$repo_root/build/scripting-languages"
dist_dir="$repo_root/dist"
evidence_path="$dist_dir/sshfling-scripting-languages-$version-validation.tsv"
current_subject="batch"
current_phase="setup"

rm -rf "$build_root"
install -d "$build_root/stage" "$build_root/install" "$build_root/projects" \
  "$build_root/probes" "$build_root/logs" "$build_root/home" "$build_root/cache" \
  "$dist_dir"
: >"$evidence_path"

cleanup() {
  rm -rf "$build_root"
}
trap cleanup EXIT

record() {
  local subject="$1"
  local phase="$2"
  local status="$3"
  local detail="${4:-}"
  detail="${detail//$'\t'/ }"
  detail="${detail//$'\n'/; }"
  printf 'RESULT\t%s\t%s\t%s\t%s\n' "$subject" "$phase" "$status" "$detail" | tee -a "$evidence_path"
}

on_error() {
  local status="$1"
  local line="$2"
  local command="$3"
  trap - ERR
  record "$current_subject" "$current_phase" "FAIL" "exit=$status line=$line command=$command"
  exit "$status"
}
trap 'on_error "$?" "$LINENO" "$BASH_COMMAND"' ERR

fail() {
  local subject="$1"
  local phase="$2"
  local detail="$3"
  record "$subject" "$phase" "FAIL" "$detail"
  exit 1
}

expect_equal() {
  local subject="$1"
  local phase="$2"
  local expected="$3"
  local actual="$4"
  if [[ "$actual" != "$expected" ]]; then
    fail "$subject" "$phase" "expected=$expected actual=$actual"
  fi
}

for required_tool in python3 tclsh awk sed tar gzip sha256sum cmp; do
  if ! command -v "$required_tool" >/dev/null 2>&1; then
    fail "batch" "tool-presence" "required-tool-missing=$required_tool"
  fi
done

source_date_epoch="${SOURCE_DATE_EPOCH:-0}"
if [[ ! "$source_date_epoch" =~ ^[0-9]+$ ]]; then
  fail "batch" "source-date-epoch" \
    "SOURCE_DATE_EPOCH must be an integer Unix timestamp; actual=$source_date_epoch"
fi

export LC_ALL=C
export TZ=UTC
export SOURCE_DATE_EPOCH="$source_date_epoch"
export HOME="$build_root/home"
export XDG_CACHE_HOME="$build_root/cache"
unset SSHFLING_RUNTIME SSHFLING_TEMPLATE_DIR SSHFLING_PYTHON SSHFLING_PACKAGE_ROOT
unset LUA_PATH LUA_CPATH TCLLIBPATH

lua_rock_produced=0

template_entries=(
  ".env.example"
  "LICENSE"
  "README.md"
  "compose.server.yml"
  "compose.client.yml"
  "native/sshfling-linux-account"
  "native/sshfling-unix-identity"
  "scripts/install-local.sh"
  "scripts/uninstall-local.sh"
  "scripts/create-network.sh"
  "scripts/generate-ssh-key.sh"
  "secrets/.gitkeep"
  "ssh-client/Dockerfile"
  "ssh-client/entrypoint.sh"
  "ssh-server/Dockerfile"
  "ssh-server/entrypoint.sh"
  "ssh-server/limited-session.sh"
  "ssh-server/sshd_config"
  "production/sshfling-login-shell"
  "production/sshfling-session"
  "systemd/sshflingd.service"
  "systemd/sshfling-prune.service"
  "systemd/sshfling-prune.timer"
  "systemd/sshflingd.env.example"
)

executable_template_entries=(
  "native/sshfling-linux-account"
  "native/sshfling-unix-identity"
  "scripts/install-local.sh"
  "scripts/uninstall-local.sh"
  "scripts/create-network.sh"
  "scripts/generate-ssh-key.sh"
  "ssh-client/entrypoint.sh"
  "ssh-server/entrypoint.sh"
  "ssh-server/limited-session.sh"
  "production/sshfling-login-shell"
  "production/sshfling-session"
)

render_file() {
  local source_path="$1"
  local destination_path="$2"
  local mode="${3:-0644}"
  install -d "$(dirname "$destination_path")"
  sed "s/0[.]0[.]0/$version/g" "$source_path" >"$destination_path"
  chmod "$mode" "$destination_path"
}

install_package_metadata() {
  local source_path="$1"
  local stage="$2"
  render_file "$source_path" "$stage/package-metadata.json"
  python3 -m json.tool "$stage/package-metadata.json" >/dev/null
  install -m 0644 "$repo_root/LICENSE" "$stage/LICENSE"
}

copy_runtime_and_templates() {
  local runtime_dir="$1"
  install -d "$runtime_dir"
  install -m 0755 "$repo_root/bin/sshfling" "$runtime_dir/sshfling.py"
  copy_sshfling_templates "$repo_root" "$runtime_dir/templates"
}

copy_common_bundle() {
  local stage="$1"
  copy_runtime_and_templates "$stage/libexec/sshfling"
  install -d "$stage/share/sshfling"
  ln -s ../../libexec/sshfling/templates "$stage/share/sshfling/templates"
}

stage_generic_cli() {
  local stage="$1"
  render_file \
    "$repo_root/packaging/shell-languages/common/sshfling-launcher.sh" \
    "$stage/bin/sshfling" 0755
}

deterministic_tar_gz() {
  local parent="$1"
  local base_name="$2"
  local destination="$3"
  local temporary="$destination.tmp.tar"

  rm -f -- "$temporary" "$temporary.gz" "$destination"
  tar -C "$parent" \
    --sort=name \
    --mtime="@$source_date_epoch" \
    --owner=0 --group=0 --numeric-owner \
    --format=posix \
    --pax-option=delete=atime,delete=ctime \
    -cf "$temporary" "$base_name"
  gzip -n -9 -- "$temporary"
  mv -- "$temporary.gz" "$destination"
}

archive_and_extract() {
  local subject="$1"
  local base_name="$2"
  local stage="$3"
  local archive="$dist_dir/$base_name.tar.gz"
  local archive_work="$build_root/archive-work/$base_name"
  local archive_candidate="$archive_work/primary/$base_name.tar.gz"
  local repeat_archive="$archive_work/repeat/$base_name.tar.gz"
  local archive_sha

  current_subject="$subject"
  current_phase="archive"
  rm -f "$archive"
  rm -rf "$archive_work"
  install -d "$(dirname "$archive_candidate")" "$(dirname "$repeat_archive")"
  deterministic_tar_gz "$(dirname "$stage")" "$base_name" "$archive_candidate"
  deterministic_tar_gz "$(dirname "$stage")" "$base_name" "$repeat_archive"
  if ! cmp "$archive_candidate" "$repeat_archive" >/dev/null; then
    fail "$subject" "archive-reproducibility" \
      "artifact=$(basename "$archive");repeat_build=different"
  fi
  install -m 0644 "$archive_candidate" "$archive"
  test -s "$archive"
  tar -tzf "$archive" | grep -Fx "$base_name/package-metadata.json" >/dev/null
  archive_sha="$(sha256sum "$archive" | awk '{print $1}')"

  rm -rf "$build_root/install/$base_name"
  tar -C "$build_root/install" -xzf "$archive"
  test -f "$build_root/install/$base_name/package-metadata.json"
  rm -rf "$stage"

  package_prefix="$build_root/install/$base_name"
  record "$subject" "package-archive" "PASS" \
    "artifact=$(basename "$archive");sha256=$archive_sha;repeat_build=identical;source_date_epoch=$source_date_epoch"
}

validate_template_tree() {
  local template_root="$1"
  local relative
  for relative in "${template_entries[@]}"; do
    cmp "$repo_root/$relative" "$template_root/$relative" >/dev/null
  done
  for relative in "${executable_template_entries[@]}"; do
    test -x "$template_root/$relative"
  done
}

validate_common_bundle() {
  local prefix="$1"
  cmp "$repo_root/bin/sshfling" "$prefix/libexec/sshfling/sshfling.py" >/dev/null
  validate_template_tree "$prefix/libexec/sshfling/templates"
  test -L "$prefix/share/sshfling/templates"
}

validate_initialized_assets() {
  local project_dir="$1"
  local relative
  for relative in "${template_entries[@]}"; do
    if ! cmp "$repo_root/$relative" "$project_dir/$relative" >/dev/null; then
      fail "$current_subject" "$current_phase" "initialized-asset-mismatch=$relative"
    fi
  done
  for relative in "${executable_template_entries[@]}"; do
    if [[ ! -x "$project_dir/$relative" ]]; then
      fail "$current_subject" "$current_phase" "initialized-asset-not-executable=$relative"
    fi
  done
  if ! grep -Fqx 'SSH_SESSION_SECONDS=60' "$project_dir/.env"; then
    fail "$current_subject" "$current_phase" "initialized-env-session-seconds-mismatch"
  fi
}

validate_cli_lifecycle() {
  local subject="$1"
  local cli_path="$2"
  local qualifier="${3:-cli}"
  local output
  local project_dir="$build_root/projects/$subject-$qualifier project"

  current_subject="$subject"
  current_phase="$qualifier-version"
  output="$("$cli_path" --version)"
  expect_equal "$subject" "$qualifier-version" "sshfling $version" "$output"
  record "$subject" "$qualifier-version" "PASS" "$output"

  current_phase="$qualifier-init-assets"
  rm -rf "$project_dir"
  "$cli_path" init "$project_dir" --force --session-seconds 60 >/dev/null
  validate_initialized_assets "$project_dir"
  record "$subject" "$qualifier-init-assets" "PASS" \
    "assets=${#template_entries[@]} executable-assets=${#executable_template_entries[@]} session-seconds=60"
  rm -rf "$project_dir"
}

validate_cli_symlink() {
  local subject="$1"
  local cli_path="$2"
  local link_path="$build_root/probes/$subject linked cli"
  local output

  current_subject="$subject"
  current_phase="symlink-cli-version"
  rm -f "$link_path"
  ln -s "$cli_path" "$link_path"
  output="$("$link_path" --version)"
  expect_equal "$subject" "$current_phase" "sshfling $version" "$output"
  rm -f "$link_path"
  record "$subject" "$current_phase" "PASS" "$output"
}

remove_isolated_package() {
  local subject="$1"
  local prefix="$2"
  local cli_path="$prefix/bin/sshfling"
  current_subject="$subject"
  current_phase="removal"
  rm -rf "$prefix"
  test ! -e "$prefix"
  test ! -e "$cli_path"
  record "$subject" "removal" "PASS" "isolated-prefix-absent=$prefix"
}

build_tcl() {
  local subject="tcl"
  local base_name="sshfling-tcl-$version"
  local stage="$build_root/stage/$base_name"
  local probe="$build_root/probes/tcl-api.tcl"
  local output

  current_subject="$subject"
  current_phase="stage"
  install -d "$stage/bin" "$stage/lib/sshfling"
  install_package_metadata "$repo_root/packaging/tcl/package-metadata.json" "$stage"
  render_file "$repo_root/packaging/tcl/sshfling.tcl" "$stage/lib/sshfling/sshfling.tcl"
  render_file "$repo_root/packaging/tcl/pkgIndex.tcl" "$stage/lib/sshfling/pkgIndex.tcl"
  render_file "$repo_root/packaging/tcl/bin/sshfling" "$stage/bin/sshfling" 0755
  copy_runtime_and_templates "$stage/lib/sshfling/runtime"
  archive_and_extract "$subject" "$base_name" "$stage"

  cmp "$repo_root/bin/sshfling" "$package_prefix/lib/sshfling/runtime/sshfling.py" >/dev/null
  validate_template_tree "$package_prefix/lib/sshfling/runtime/templates"

  cat >"$probe" <<'EOF'
set root [lindex $argv 0]
set expected [lindex $argv 1]
lappend auto_path [file join $root lib sshfling]
package require -exact sshfling $expected
puts [::sshfling::version]
exit [::sshfling::run --version]
EOF
  current_phase="package-require-runtime"
  output="$(TCLLIBPATH="$package_prefix/lib/sshfling" tclsh "$probe" "$package_prefix" "$version")"
  expect_equal "$subject" "$current_phase" "$version"$'\n'"sshfling $version" "$output"
  record "$subject" "$current_phase" "PASS" "package=$version runtime=sshfling-$version"

  validate_cli_lifecycle "$subject" "$package_prefix/bin/sshfling"
  validate_cli_symlink "$subject" "$package_prefix/bin/sshfling"
  remove_isolated_package "$subject" "$package_prefix"
  if TCLLIBPATH="$package_prefix/lib/sshfling" tclsh "$probe" "$package_prefix" "$version" >/dev/null 2>&1; then
    fail "$subject" "removal-import" "package remained importable after prefix removal"
  fi
  record "$subject" "removal-import" "PASS" "package-require-fails-after-removal"
}

build_awk() {
  local subject="awk"
  local base_name="sshfling-awk-$version"
  local stage="$build_root/stage/$base_name"
  local probe="$build_root/probes/awk-api.awk"
  local output

  current_subject="$subject"
  current_phase="stage"
  install -d "$stage/bin" "$stage/share/sshfling/awk"
  install_package_metadata "$repo_root/packaging/awk/package-metadata.json" "$stage"
  render_file "$repo_root/packaging/awk/sshfling.awk" "$stage/share/sshfling/awk/sshfling.awk"
  install -m 0644 "$repo_root/packaging/awk/cli.awk" "$stage/share/sshfling/awk/cli.awk"
  install -m 0755 "$repo_root/packaging/awk/sshfling" "$stage/bin/sshfling"
  copy_common_bundle "$stage"
  archive_and_extract "$subject" "$base_name" "$stage"
  validate_common_bundle "$package_prefix"

  cat >"$probe" <<'EOF'
BEGIN {
    if (sshfling_version() != ENVIRON["EXPECTED_VERSION"]) exit 2
    if (sshfling_runtime_path() == "" || sshfling_template_dir() == "") exit 3
    arguments[1] = "--version"
    exit sshfling_run(arguments, 1)
}
EOF
  current_phase="source-runtime"
  output="$(SSHFLING_PACKAGE_ROOT="$package_prefix" EXPECTED_VERSION="$version" \
    awk -f "$package_prefix/share/sshfling/awk/sshfling.awk" -f "$probe")"
  expect_equal "$subject" "$current_phase" "sshfling $version" "$output"
  record "$subject" "$current_phase" "PASS" "mawk-compatible-source-api; $output"

  validate_cli_lifecycle "$subject" "$package_prefix/bin/sshfling"
  validate_cli_symlink "$subject" "$package_prefix/bin/sshfling"
  remove_isolated_package "$subject" "$package_prefix"
  test ! -e "$package_prefix/share/sshfling/awk/sshfling.awk"
  record "$subject" "removal-source" "PASS" "source-file-absent"
}

build_sed() {
  local subject="sed"
  local base_name="sshfling-sed-$version"
  local stage="$build_root/stage/$base_name"
  local output filtered rejected

  current_subject="$subject"
  current_phase="stage"
  install -d "$stage/share/sshfling/sed"
  install_package_metadata "$repo_root/packaging/sed/package-metadata.json" "$stage"
  install -m 0644 "$repo_root/packaging/sed/sshfling-version.sed" \
    "$stage/share/sshfling/sed/sshfling-version.sed"
  stage_generic_cli "$stage"
  copy_common_bundle "$stage"
  archive_and_extract "$subject" "$base_name" "$stage"
  validate_common_bundle "$package_prefix"

  current_phase="source-filter"
  output="$("$package_prefix/bin/sshfling" --version)"
  filtered="$(printf '%s\n' "$output" | sed -n -f "$package_prefix/share/sshfling/sed/sshfling-version.sed")"
  rejected="$(printf '%s\n' 'not sshfling 1.2.3' | sed -n -f "$package_prefix/share/sshfling/sed/sshfling-version.sed")"
  expect_equal "$subject" "$current_phase" "$version" "$filtered"
  expect_equal "$subject" "$current_phase" "" "$rejected"
  record "$subject" "$current_phase" "PASS" "input=$output extracted=$filtered invalid-output=empty"

  validate_cli_lifecycle "$subject" "$package_prefix/bin/sshfling"
  validate_cli_symlink "$subject" "$package_prefix/bin/sshfling"
  remove_isolated_package "$subject" "$package_prefix"
  test ! -e "$package_prefix/share/sshfling/sed/sshfling-version.sed"
  record "$subject" "removal-source" "PASS" "sed-command-file-absent"
}

lua_path_for_tree() {
  local tree="$1"
  local abi="$2"
  printf '%s\n' "$tree/share/lua/$abi/?.lua;$tree/share/lua/$abi/?/init.lua"
}

pack_lua_rock() {
  local abi="$1"
  local tree="$2"
  local output_dir="$3"
  local log_path="$4"
  local expected_rock="$output_dir/sshfling-$version-1.all.rock"
  local -a packed_rocks=()

  rm -rf "$output_dir"
  install -d "$output_dir"
  if ! (cd "$output_dir" && luarocks --lua-version="$abi" --tree="$tree" \
      pack sshfling "$version-1" >"$log_path" 2>&1); then
    cat "$log_path" >&2
    fail "lua" "luarocks-pack" "luarocks-pack-failed"
  fi

  shopt -s nullglob
  packed_rocks=("$output_dir"/sshfling-"$version"-1.*.rock)
  shopt -u nullglob
  if ((${#packed_rocks[@]} != 1)) || [[ ! -s "$expected_rock" ]]; then
    fail "lua" "luarocks-pack" \
      "expected-one-all-rock; produced=${#packed_rocks[@]}"
  fi
}

normalize_lua_rock() {
  local source="$1"
  local destination="$2"

  python3 - "$source" "$destination" "$source_date_epoch" <<'PY'
from __future__ import annotations

import calendar
import stat
import sys
import time
import zipfile
from pathlib import Path, PurePosixPath


source = Path(sys.argv[1])
destination = Path(sys.argv[2])
source_date_epoch = int(sys.argv[3])
temporary = destination.with_name(destination.name + ".tmp")

if source.resolve() == destination.resolve():
    raise SystemExit("Lua rock normalization requires distinct input and output paths")
if not zipfile.is_zipfile(source):
    raise SystemExit(f"Lua rock is not a ZIP archive: {source}")

zip_min_epoch = calendar.timegm((1980, 1, 1, 0, 0, 0))
zip_max_epoch = calendar.timegm((2107, 12, 31, 23, 59, 58))
zip_epoch = min(max(source_date_epoch, zip_min_epoch), zip_max_epoch)
timestamp = time.gmtime(zip_epoch)
date_time = (
    timestamp.tm_year,
    timestamp.tm_mon,
    timestamp.tm_mday,
    timestamp.tm_hour,
    timestamp.tm_min,
    timestamp.tm_sec - (timestamp.tm_sec % 2),
)

if temporary.exists():
    temporary.unlink()

try:
    with zipfile.ZipFile(source, "r") as reader:
        entries = reader.infolist()
        names = [entry.filename for entry in entries]
        if len(names) != len(set(names)):
            raise SystemExit("Lua rock contains duplicate ZIP entries")

        with zipfile.ZipFile(temporary, "w") as writer:
            for original in sorted(entries, key=lambda entry: entry.filename.encode("utf-8")):
                name = original.filename
                archive_path = PurePosixPath(name)
                if not name or archive_path.is_absolute() or ".." in archive_path.parts:
                    raise SystemExit(f"Lua rock contains an unsafe ZIP entry: {name!r}")
                if original.flag_bits & 0x1:
                    raise SystemExit(f"Lua rock contains an encrypted ZIP entry: {name}")

                original_mode = (original.external_attr >> 16) & 0xFFFF
                if original.is_dir():
                    payload = b""
                    mode = stat.S_IFDIR | 0o755
                    compression = zipfile.ZIP_STORED
                else:
                    file_type = stat.S_IFMT(original_mode)
                    if file_type not in (0, stat.S_IFREG):
                        raise SystemExit(
                            f"Lua rock contains an unsupported ZIP entry type: {name}"
                        )
                    payload = reader.read(original)
                    permissions = 0o755 if original_mode & 0o111 else 0o644
                    mode = stat.S_IFREG | permissions
                    compression = zipfile.ZIP_DEFLATED

                normalized = zipfile.ZipInfo(name, date_time=date_time)
                normalized.create_system = 3
                normalized.create_version = 20
                normalized.extract_version = 20
                normalized.compress_type = compression
                normalized.external_attr = (mode & 0xFFFF) << 16
                if original.is_dir():
                    normalized.external_attr |= 0x10
                normalized.internal_attr = 0
                normalized.extra = b""
                normalized.comment = b""

                if compression == zipfile.ZIP_DEFLATED:
                    writer.writestr(normalized, payload, compresslevel=9)
                else:
                    writer.writestr(normalized, payload)

    with zipfile.ZipFile(temporary, "r") as normalized_rock:
        corrupt_entry = normalized_rock.testzip()
        if corrupt_entry is not None:
            raise SystemExit(f"normalized Lua rock has a corrupt entry: {corrupt_entry}")
    temporary.replace(destination)
finally:
    if temporary.exists():
        temporary.unlink()
PY
}

validate_packed_lua_rock() {
  local lua_command="$1"
  local abi="$2"
  local rock="$3"
  local packed_tree="$build_root/luarocks-packed-$abi"
  local lua_path output project_dir

  current_subject="lua"
  current_phase="lua-$abi-packed-rock-install"
  rm -rf "$packed_tree"
  install -d "$packed_tree"
  luarocks --lua-version="$abi" --tree="$packed_tree" install "$rock" \
    --deps-mode=none >"$build_root/logs/luarocks-packed-install-$abi.log" 2>&1
  lua_path="$(lua_path_for_tree "$packed_tree" "$abi")"
  output="$(LUA_PATH="$lua_path" LUA_CPATH="" "$lua_command" -e \
    'local s=require("sshfling"); print(s.version()); io.stdout:flush(); os.exit(s.run({"--version"}))')"
  expect_equal "lua" "$current_phase" "$version"$'\n'"sshfling $version" "$output"
  record "lua" "$current_phase" "PASS" \
    "artifact=$(basename "$rock") require-version=$version runtime=sshfling-$version"

  current_phase="lua-$abi-packed-rock-read-only-init"
  chmod -R a-w "$packed_tree/share/lua/$abi/sshfling/runtime"
  project_dir="$build_root/projects/lua-$abi-packed-rock project"
  rm -rf "$project_dir"
  "$packed_tree/bin/sshfling" init "$project_dir" --force --session-seconds 60 >/dev/null
  validate_initialized_assets "$project_dir"
  record "lua" "$current_phase" "PASS" \
    "artifact=$(basename "$rock") read-only-package-tree assets=${#template_entries[@]} executable-assets=${#executable_template_entries[@]}"
  rm -rf "$project_dir"
  chmod -R u+w "$packed_tree"

  current_phase="lua-$abi-packed-rock-removal"
  luarocks --lua-version="$abi" --tree="$packed_tree" remove sshfling "$version-1" \
    --force >"$build_root/logs/luarocks-packed-remove-$abi.log" 2>&1
  test ! -e "$packed_tree/bin/sshfling"
  if LUA_PATH="$lua_path" LUA_CPATH="" "$lua_command" -e 'require("sshfling")' >/dev/null 2>&1; then
    fail "lua" "$current_phase" "packed rock remained importable after removal"
  fi
  record "lua" "$current_phase" "PASS" "packed-rock-module-and-cli-unavailable"
}

luarocks_headers_available() {
  local abi="$1"
  local include_dir
  include_dir="$(luarocks --lua-version="$abi" config variables.LUA_INCDIR 2>/dev/null || true)"
  [[ -n "$include_dir" && -f "$include_dir/lua.h" ]]
}

validate_lua_runtime() {
  local lua_command="$1"
  local abi="$2"
  local prefix="$3"
  local rockspec="$prefix/sshfling-$version-1.rockspec"
  local tree="$build_root/luarocks-$abi"
  local lua_path output project_dir rock_root primary_output repeat_output
  local rock_name primary_rock repeat_rock normalized_primary normalized_repeat
  local published_rock rock_sha

  current_subject="lua"
  current_phase="lua-$abi-luarocks-install"
  install -d "$tree"
  if ! (cd "$prefix" && luarocks --lua-version="$abi" --tree="$tree" \
      make "$rockspec" --deps-mode=none >"$build_root/logs/luarocks-$abi.log" 2>&1); then
    cat "$build_root/logs/luarocks-$abi.log" >&2
    fail "lua" "$current_phase" "luarocks-make-failed"
  fi
  lua_path="$(lua_path_for_tree "$tree" "$abi")"
  output="$(LUA_PATH="$lua_path" LUA_CPATH="" "$lua_command" -e \
    'local s=require("sshfling"); print(s.version()); io.stdout:flush(); os.exit(s.run({"--version"}))')"
  expect_equal "lua" "$current_phase" "$version"$'\n'"sshfling $version" "$output"
  test -x "$tree/bin/sshfling"
  record "lua" "$current_phase" "PASS" "lua=$abi require-version=$version runtime=sshfling-$version"

  current_phase="lua-$abi-init-assets"
  project_dir="$build_root/projects/lua-$abi-rock project"
  rm -rf "$project_dir"
  if ! "$tree/bin/sshfling" init "$project_dir" --force --session-seconds 60 >/dev/null; then
    fail "lua" "$current_phase" "installed-luarocks-cli-init-failed"
  fi
  validate_initialized_assets "$project_dir"
  record "lua" "$current_phase" "PASS" \
    "assets=${#template_entries[@]} executable-assets=${#executable_template_entries[@]}"
  rm -rf "$project_dir"

  if [[ "$abi" == "5.1" ]]; then
    current_phase="luarocks-package-reproducibility"
    rock_root="$build_root/rock-output"
    primary_output="$rock_root/primary"
    repeat_output="$rock_root/repeat"
    rock_name="sshfling-$version-1.all.rock"
    primary_rock="$primary_output/$rock_name"
    repeat_rock="$repeat_output/$rock_name"
    normalized_primary="$rock_root/normalized-primary/$rock_name"
    normalized_repeat="$rock_root/normalized-repeat/$rock_name"

    rm -rf "$rock_root"
    pack_lua_rock "$abi" "$tree" "$primary_output" \
      "$build_root/logs/luarocks-pack-primary.log"
    pack_lua_rock "$abi" "$tree" "$repeat_output" \
      "$build_root/logs/luarocks-pack-repeat.log"
    install -d "$(dirname "$normalized_primary")" "$(dirname "$normalized_repeat")"
    normalize_lua_rock "$primary_rock" "$normalized_primary"
    normalize_lua_rock "$repeat_rock" "$normalized_repeat"
    if ! cmp "$normalized_primary" "$normalized_repeat" >/dev/null; then
      fail "lua" "$current_phase" \
        "artifact=$rock_name;repeat_build=different"
    fi

    published_rock="$dist_dir/$rock_name"
    install -m 0644 "$normalized_primary" "$published_rock"
    rock_sha="$(sha256sum "$published_rock" | awk '{print $1}')"
    record "lua" "luarocks-package" "PASS" \
      "artifact=$rock_name;sha256=$rock_sha;repeat_build=identical;container=zip;metadata=normalized;source_date_epoch=$source_date_epoch"
    validate_packed_lua_rock "$lua_command" "$abi" "$published_rock"
    lua_rock_produced=1
  fi

  current_phase="lua-$abi-removal"
  luarocks --lua-version="$abi" --tree="$tree" remove sshfling "$version-1" \
    --force >"$build_root/logs/luarocks-remove-$abi.log" 2>&1
  test ! -e "$tree/bin/sshfling"
  if LUA_PATH="$lua_path" LUA_CPATH="" "$lua_command" -e 'require("sshfling")' >/dev/null 2>&1; then
    fail "lua" "$current_phase" "module remained importable after luarocks remove"
  fi
  record "lua" "$current_phase" "PASS" "luarocks-remove; module-and-cli-unavailable"
}

build_lua() {
  local subject="lua"
  local base_name="sshfling-lua-$version"
  local stage="$build_root/stage/$base_name"
  local rockspec_name="sshfling-$version-1.rockspec"
  local lua_command abi output project_dir

  current_subject="$subject"
  current_phase="stage"
  install -d "$stage/bin" "$stage/lua/sshfling"
  install_package_metadata "$repo_root/packaging/lua/package-metadata.json" "$stage"
  render_file "$repo_root/packaging/lua/lua/sshfling/init.lua" "$stage/lua/sshfling/init.lua"
  render_file "$repo_root/packaging/lua/bin/sshfling" "$stage/bin/sshfling" 0755
  render_file "$repo_root/packaging/lua/sshfling-0.0.0-1.rockspec" "$stage/$rockspec_name"
  copy_runtime_and_templates "$stage/lua/sshfling/runtime"
  archive_and_extract "$subject" "$base_name" "$stage"
  cmp "$repo_root/bin/sshfling" "$package_prefix/lua/sshfling/runtime/sshfling.py" >/dev/null
  validate_template_tree "$package_prefix/lua/sshfling/runtime/templates"

  if ! command -v luarocks >/dev/null 2>&1; then
    record "$subject" "luarocks-package" "SKIP" "tool-not-found=luarocks"
  fi

  for lua_command in lua5.1 lua5.4; do
    if ! command -v "$lua_command" >/dev/null 2>&1; then
      record "$subject" "$lua_command-runtime" "SKIP" "tool-not-found=$lua_command"
      continue
    fi
    abi="${lua_command#lua}"
    current_phase="$lua_command-source-runtime"
    output="$(LUA_PATH="$package_prefix/lua/?.lua;$package_prefix/lua/?/init.lua" LUA_CPATH="" \
      "$lua_command" -e 'local s=require("sshfling"); print(s.version()); io.stdout:flush(); os.exit(s.run({"--version"}))')"
    expect_equal "$subject" "$current_phase" "$version"$'\n'"sshfling $version" "$output"
    record "$subject" "$current_phase" "PASS" "require-version=$version runtime=sshfling-$version"

    current_phase="$lua_command-source-init-assets"
    project_dir="$build_root/projects/$lua_command-source project"
    rm -rf "$project_dir"
    "$lua_command" "$package_prefix/bin/sshfling" \
      init "$project_dir" --force --session-seconds 60 >/dev/null
    validate_initialized_assets "$project_dir"
    record "$subject" "$current_phase" "PASS" \
      "assets=${#template_entries[@]} executable-assets=${#executable_template_entries[@]}"
    rm -rf "$project_dir"

    if ! command -v luarocks >/dev/null 2>&1; then
      record "$subject" "lua-$abi-luarocks-install" "SKIP" "tool-not-found=luarocks"
      continue
    fi
    if ! luarocks_headers_available "$abi"; then
      record "$subject" "lua-$abi-luarocks-install" "SKIP" \
        "dependency-missing=lua-$abi-development-headers; source-library-and-cli-runtime=PASS"
      continue
    fi
    validate_lua_runtime "$lua_command" "$abi" "$package_prefix"
  done

  if ((lua_rock_produced == 0)); then
    fail "$subject" "luarocks-package" "required .rock artifact was not produced and reinstalled"
  fi

  validate_cli_symlink "$subject" "$package_prefix/bin/sshfling"
  remove_isolated_package "$subject" "$package_prefix"
  test ! -e "$package_prefix/lua/sshfling/init.lua"
  record "$subject" "removal-source" "PASS" "source-module-absent"
}

validate_zsh_source() {
  local prefix="$1"
  local module="$prefix/share/sshfling/zsh/sshfling.zsh"
  local project="$build_root/projects/zsh-source project"
  local output
  output="$(SSHFLING_PACKAGE_ROOT="$prefix" zsh -c \
    'source "$1"; [[ "$(sshfling_version)" == "$2" ]] || exit 2; sshfling_run --version' \
    zsh "$module" "$version")"
  expect_equal "zsh" "source-runtime" "sshfling $version" "$output"
  SSHFLING_PACKAGE_ROOT="$prefix" zsh -c \
    'source "$1"; sshfling_run init "$2" --force --session-seconds 60 >/dev/null' \
    zsh "$module" "$project"
  validate_initialized_assets "$project"
  rm -rf "$project"
  record "zsh" "source-runtime" "PASS" "zsh=$(zsh --version); $output; init-assets=${#template_entries[@]}"
}

validate_fish_source() {
  local prefix="$1"
  local module="$prefix/share/sshfling/fish/sshfling.fish"
  local project="$build_root/projects/fish-source project"
  local output
  # The Fish expressions are intentionally passed through without Bash expansion.
  # shellcheck disable=SC2016
  output="$(SSHFLING_PACKAGE_ROOT="$prefix" fish -c \
    'source $argv[1]; or exit 1; test (sshfling_version) = $argv[2]; or exit 2; sshfling_run --version' \
    "$module" "$version")"
  expect_equal "fish" "source-runtime" "sshfling $version" "$output"
  # shellcheck disable=SC2016
  SSHFLING_PACKAGE_ROOT="$prefix" fish -c \
    'source $argv[1]; or exit 1; sshfling_run init $argv[2] --force --session-seconds 60 >/dev/null' \
    "$module" "$project"
  validate_initialized_assets "$project"
  rm -rf "$project"
  record "fish" "source-runtime" "PASS" "fish=$(fish --version); $output; init-assets=${#template_entries[@]}"
}

validate_elvish_source() {
  local prefix="$1"
  local project="$build_root/projects/elvish-source project"
  local probe="$build_root/probes/elvish-runtime.elv"
  local output
  cat >"$probe" <<'EOF'
use sshfling
if (not-eq (sshfling:version) $args[0]) { fail 'version mismatch' }
sshfling:run --version
sshfling:run init $args[1] --force --session-seconds 60 >/dev/null
EOF
  output="$(XDG_DATA_HOME="$prefix/share" SSHFLING_PACKAGE_ROOT="$prefix" \
    elvish "$probe" "$version" "$project")"
  expect_equal "elvish" "source-runtime" "sshfling $version" "$output"
  validate_initialized_assets "$project"
  rm -rf "$project"
  record "elvish" "source-runtime" "PASS" "$output; init-assets=${#template_entries[@]}"
}

validate_nushell_source() {
  local prefix="$1"
  local module="$prefix/share/sshfling/nushell/sshfling.nu"
  local project="$build_root/projects/nushell-source project"
  local probe="$build_root/probes/nushell-runtime.nu"
  local output
  cat >"$probe" <<EOF
use '$module' *
if (sshfling-version) != '$version' { error make {msg: 'version mismatch'} }
sshfling-run --version
sshfling-run init '$project' --force --session-seconds 60 | ignore
EOF
  output="$(SSHFLING_PACKAGE_ROOT="$prefix" nu "$probe")"
  expect_equal "nushell" "source-runtime" "sshfling $version" "$output"
  validate_initialized_assets "$project"
  rm -rf "$project"
  record "nushell" "source-runtime" "PASS" "$output; init-assets=${#template_entries[@]}"
}

validate_powershell_source() {
  local prefix="$1"
  local module="$prefix/share/powershell/Modules/SSHFling/SSHFling.psd1"
  local native_cli="$prefix/bin/sshfling.ps1"
  local project="$build_root/projects/powershell-source project"
  local probe="$build_root/probes/powershell-runtime.ps1"
  local output
  cat >"$probe" <<'EOF'
param([string] $ModulePath, [string] $ExpectedVersion)
$ErrorActionPreference = 'Stop'
Import-Module $ModulePath -Force
if ((Get-SSHFlingVersion) -ne $ExpectedVersion) { throw 'version mismatch' }
exit 0
EOF
  SSHFLING_PACKAGE_ROOT="$prefix" pwsh -NoLogo -NoProfile -File "$probe" \
    -ModulePath "$module" -ExpectedVersion "$version"
  output="$(pwsh -NoLogo -NoProfile -File "$native_cli" --version)"
  expect_equal "powershell" "source-runtime" "sshfling $version" "$output"
  pwsh -NoLogo -NoProfile -File "$native_cli" \
    init "$project" --force --session-seconds 60 >/dev/null
  validate_initialized_assets "$project"
  rm -rf "$project"
  record "powershell" "source-runtime" "PASS" "$output; init-assets=${#template_entries[@]}"
}

build_shell_package() {
  local subject="$1"
  local interpreter="$2"
  local source_path="$3"
  local module_relative="$4"
  local base_name="sshfling-$subject-$version"
  local stage="$build_root/stage/$base_name"

  current_subject="$subject"
  current_phase="stage"
  install_package_metadata \
    "$repo_root/packaging/shell-languages/$subject/package-metadata.json" "$stage"
  render_file "$source_path" "$stage/$module_relative"
  if [[ "$subject" == "powershell" ]]; then
    render_file \
      "$repo_root/packaging/shell-languages/powershell/SSHFling.psd1" \
      "$stage/share/powershell/Modules/SSHFling/SSHFling.psd1"
    render_file \
      "$repo_root/packaging/shell-languages/powershell/sshfling.ps1" \
      "$stage/bin/sshfling.ps1"
  fi
  stage_generic_cli "$stage"
  copy_common_bundle "$stage"
  archive_and_extract "$subject" "$base_name" "$stage"
  validate_common_bundle "$package_prefix"
  validate_cli_lifecycle "$subject" "$package_prefix/bin/sshfling" "package-cli"
  validate_cli_symlink "$subject" "$package_prefix/bin/sshfling"

  current_phase="source-runtime"
  if ! command -v "$interpreter" >/dev/null 2>&1; then
    record "$subject" "source-runtime" "SKIP" "tool-not-found=$interpreter"
  else
    case "$subject" in
      zsh) validate_zsh_source "$package_prefix" ;;
      fish) validate_fish_source "$package_prefix" ;;
      elvish) validate_elvish_source "$package_prefix" ;;
      nushell) validate_nushell_source "$package_prefix" ;;
      powershell) validate_powershell_source "$package_prefix" ;;
      *) fail "$subject" "source-runtime" "unknown-shell-validator" ;;
    esac
  fi

  remove_isolated_package "$subject" "$package_prefix"
  test ! -e "$package_prefix/$module_relative"
  record "$subject" "removal-source" "PASS" "source-module-absent"
}

validate_guile_source() {
  local prefix="$1"
  local project="$build_root/projects/guix-scheme-source project"
  local output
  output="$(GUILE_LOAD_PATH="$prefix/share/guile/site/3.0" \
    SSHFLING_PACKAGE_ROOT="$prefix" EXPECTED_VERSION="$version" guile -c \
    '(use-modules (sshfling))
     (unless (string=? (sshfling-version) (getenv "EXPECTED_VERSION")) (exit 2))
     (exit (sshfling-run (list "--version")))')"
  expect_equal "guix-scheme" "guile-runtime" "sshfling $version" "$output"
  GUILE_LOAD_PATH="$prefix/share/guile/site/3.0" SSHFLING_PACKAGE_ROOT="$prefix" \
    PROJECT_PATH="$project" guile -c \
    '(use-modules (sshfling))
     (exit (sshfling-run (list "init" (getenv "PROJECT_PATH") "--force"
                               "--session-seconds" "60")))' >/dev/null
  validate_initialized_assets "$project"
  rm -rf "$project"
  record "guix-scheme" "guile-runtime" "PASS" "$output; init-assets=${#template_entries[@]}"
}

build_guix_scheme() {
  local subject="guix-scheme"
  local base_name="sshfling-guix-scheme-$version"
  local stage="$build_root/stage/$base_name"

  current_subject="$subject"
  current_phase="stage"
  install_package_metadata "$repo_root/packaging/guix-scheme/package-metadata.json" "$stage"
  render_file "$repo_root/packaging/guix-scheme/sshfling.scm" \
    "$stage/share/guile/site/3.0/sshfling.scm"
  render_file "$repo_root/packaging/guix-scheme/sshfling-package.scm" \
    "$stage/sshfling-package.scm"
  stage_generic_cli "$stage"
  copy_common_bundle "$stage"
  archive_and_extract "$subject" "$base_name" "$stage"
  validate_common_bundle "$package_prefix"
  validate_cli_lifecycle "$subject" "$package_prefix/bin/sshfling" "package-cli"
  validate_cli_symlink "$subject" "$package_prefix/bin/sshfling"

  current_phase="guile-runtime"
  if command -v guile >/dev/null 2>&1; then
    validate_guile_source "$package_prefix"
  else
    record "$subject" "guile-runtime" "SKIP" "tool-not-found=guile"
  fi

  current_phase="guix-definition"
  if command -v guix >/dev/null 2>&1; then
    guix build --dry-run --no-substitutes -f "$package_prefix/sshfling-package.scm" >/dev/null
    record "$subject" "guix-definition" "PASS" "guix-dry-run"
  else
    record "$subject" "guix-definition" "SKIP" "tool-not-found=guix"
  fi

  remove_isolated_package "$subject" "$package_prefix"
  test ! -e "$package_prefix/share/guile/site/3.0/sshfling.scm"
  record "$subject" "removal-source" "PASS" "guile-module-and-guix-definition-absent"
}

record "batch" "source-version" "PASS" "$version"
record "batch" "required-tools" "PASS" \
  "python3=$(python3 --version 2>&1); tcl=$(printf 'puts [info patchlevel]\n' | tclsh); awk=$(command -v awk); sed=$(command -v sed)"

build_tcl
build_awk
build_sed
build_lua
build_shell_package \
  "zsh" "zsh" \
  "$repo_root/packaging/shell-languages/zsh/sshfling.zsh" \
  "share/sshfling/zsh/sshfling.zsh"
build_shell_package \
  "fish" "fish" \
  "$repo_root/packaging/shell-languages/fish/sshfling.fish" \
  "share/sshfling/fish/sshfling.fish"
build_shell_package \
  "elvish" "elvish" \
  "$repo_root/packaging/shell-languages/elvish/sshfling.elv" \
  "share/elvish/lib/sshfling.elv"
build_shell_package \
  "nushell" "nu" \
  "$repo_root/packaging/shell-languages/nushell/sshfling.nu" \
  "share/sshfling/nushell/sshfling.nu"
build_shell_package \
  "powershell" "pwsh" \
  "$repo_root/packaging/shell-languages/powershell/SSHFling.psm1" \
  "share/powershell/Modules/SSHFling/SSHFling.psm1"

current_subject="powershell"
current_phase="manifest-presence"
powershell_archive="$dist_dir/sshfling-powershell-$version.tar.gz"
tar -tzf "$powershell_archive" | grep -Fx \
  "sshfling-powershell-$version/share/powershell/Modules/SSHFling/SSHFling.psd1" >/dev/null
tar -tzf "$powershell_archive" | grep -Fx \
  "sshfling-powershell-$version/bin/sshfling.ps1" >/dev/null
record "powershell" "manifest-source" "PASS" \
  "archive-module-manifest=SSHFling.psd1 native-cli=bin/sshfling.ps1"

build_guix_scheme

record "batch" "summary" "PASS" \
  "archives=10; see interpreter-specific PASS/SKIP rows; build-workspace-cleaned-on-exit"
printf 'EVIDENCE\t%s\n' "$evidence_path"
