#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
systems_root="$repo_root/packaging/systems-languages"
registry="$systems_root/packages.tsv"

declare -A requested=()
list_only=0
allow_blocked=0
while (($# > 0)); do
  case "$1" in
    --language)
      if (($# < 2)); then
        echo "--language requires a package slug." >&2
        exit 2
      fi
      requested["$2"]=1
      shift 2
      ;;
    --list)
      list_only=1
      shift
      ;;
    --allow-blocked)
      allow_blocked=1
      shift
      ;;
    --help|-h)
      printf 'Usage: %s [--list] [--allow-blocked] [--language SLUG ...]\n' "$0"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if ((list_only)); then
  awk -F '|' '!/^#/ {printf "%s\t%s\n", $1, $2}' "$registry"
  exit 0
fi

for required in bash python3 install mktemp tar gzip sha256sum find sort cmp sed; do
  if ! command -v "$required" >/dev/null 2>&1; then
    echo "$required is required to validate systems-language packages." >&2
    exit 127
  fi
done

# shellcheck source=packaging/version.sh
# shellcheck disable=SC1091
source "$repo_root/packaging/version.sh"
version="$(assert_sshfling_version_matches_source "${SSHFLING_VERSION:-}" "$repo_root")"
version_define="-DSSHFLING_VERSION=\"$version\""

source_date_epoch="${SOURCE_DATE_EPOCH:-0}"
if [[ ! "$source_date_epoch" =~ ^[0-9]+$ ]]; then
  echo "SOURCE_DATE_EPOCH must be an integer Unix timestamp." >&2
  exit 2
fi
export LC_ALL=C
export TZ=UTC

dist_dir="$repo_root/dist"
evidence_path="$dist_dir/sshfling-systems-languages-$version-validation.tsv"
install -d "$dist_dir"
printf 'record\tsubject\tphase\tstatus\tdetail\n' >"$evidence_path"

record_validation() {
  local subject="$1"
  local phase="$2"
  local status="$3"
  local detail="${4:-}"
  detail="${detail//$'\t'/ }"
  detail="${detail//$'\n'/; }"
  printf 'RESULT\t%s\t%s\t%s\t%s\n' \
    "$subject" "$phase" "$status" "$detail" >>"$evidence_path"
}

record_validation batch source-version PASS "version=$version"

work_root="$(mktemp -d "${TMPDIR:-/tmp}/sshfling-systems.XXXXXX")"
cleanup() {
  if [[ -n "${work_root:-}" && -d "$work_root" ]]; then
    rm -rf -- "$work_root"
  fi
}
trap cleanup EXIT HUP INT TERM

# shellcheck source=packaging/copy-templates.sh
# shellcheck disable=SC1091
source "$repo_root/packaging/copy-templates.sh"

declare -A package_roots=()
declare -Ar validation_modes=(
  [assembly]="build-only"
  [objective-c]="build-only"
  [fortran]="build-only"
  [object-pascal]="build-only"
  [cobol]="build-only"
  [ada]="build-only"
  [zig]="build-only"
  [nim]="build-only"
  [d]="build-only"
  [v]="archive-lifecycle"
  [crystal]="build-only"
  [webassembly-wasi]="archive-lifecycle"
  [forth]="build-only"
  [odin]="archive-lifecycle"
  [pony]="archive-lifecycle"
  [chapel]="archive-lifecycle"
  [harbour]="build-only"
  [red]="build-only"
  [swift]="archive-lifecycle"
)
declare -Ar validation_capabilities=(
  [assembly]="compile,library-build,library-consumer,cli-runtime,init-workflow,exit-workflow,binary-format"
  [objective-c]="compile,library-build,library-consumer,cli-runtime,init-workflow,exit-workflow"
  [fortran]="compile,cli-runtime,init-workflow,exit-workflow"
  [object-pascal]="compile,library-consumer,cli-runtime,init-workflow,exit-workflow"
  [cobol]="compile,cli-runtime,init-workflow,exit-workflow"
  [ada]="compile,cli-runtime,init-workflow,exit-workflow"
  [zig]="compile,library-build,cli-runtime,init-workflow,exit-workflow"
  [nim]="compile,package-metadata,cli-runtime,init-workflow,exit-workflow"
  [d]="compile,library-build,cli-runtime,init-workflow,exit-workflow"
  [v]="compile,library-consumer,cli-runtime,init-workflow,exit-workflow,archive-install,isolated-consumer,remove,post-removal-import-failure"
  [crystal]="compile,cli-runtime,init-workflow,exit-workflow"
  [webassembly-wasi]="compile,library-build,library-consumer,cli-runtime,init-workflow,exit-workflow,archive-install,isolated-consumer,remove,post-removal-import-failure"
  [forth]="compile,library-runtime,cli-runtime,init-workflow,exit-workflow"
  [odin]="compile,library-build,library-consumer,cli-runtime,init-workflow,exit-workflow,archive-install,isolated-consumer,remove,post-removal-import-failure"
  [pony]="compile,library-build,library-consumer,cli-runtime,init-workflow,exit-workflow,archive-install,isolated-consumer,remove,post-removal-import-failure"
  [chapel]="compile,library-consumer,cli-runtime,init-workflow,exit-workflow,archive-install,isolated-consumer,remove,post-removal-import-failure"
  [harbour]="compile,cli-runtime,init-workflow,exit-workflow"
  [red]="compile,cli-runtime,init-workflow,exit-workflow"
  [swift]="compile,library-consumer,cli-runtime,init-workflow,exit-workflow,archive-install,isolated-consumer,remove,post-removal-import-failure"
)

runtime_validation_detail() {
  local slug="$1"
  printf 'builder_exit=0;mode=%s;capabilities=%s' \
    "${validation_modes[$slug]}" "${validation_capabilities[$slug]}"
}

deterministic_tar_gz() {
  local parent="$1"
  local base_name="$2"
  local destination="$3"
  local temporary="$destination.tar"

  rm -f -- "$temporary" "$destination"
  tar -C "$parent" \
    --sort=name \
    --mtime="@$source_date_epoch" \
    --owner=0 --group=0 --numeric-owner \
    --format=posix \
    --pax-option=delete=atime,delete=ctime \
    -cf "$temporary" "$base_name"
  gzip -n -9 "$temporary"
  mv -- "$temporary.gz" "$destination"
}

create_source_archive() {
  local slug="$1"
  local metadata="$2"
  local base_name="sshfling-$slug-$version"
  local stage_parent="$work_root/archive-stage-$slug"
  local stage="$stage_parent/$base_name"
  local extract_parent="$work_root/archive-extract-$slug"
  local extracted="$extract_parent/$base_name"
  local archive="$dist_dir/$base_name.tar.gz"
  local repeat="$work_root/$base_name-repeat.tar.gz"
  local manifest="$work_root/$slug-SOURCE-MANIFEST.sha256"
  local expected_inventory="$work_root/$slug-expected.inventory"
  local extracted_inventory="$work_root/$slug-extracted.inventory"
  local archive_sha inventory_sha file_count

  rm -rf -- "$stage_parent" "$extract_parent"
  install -d "$stage" "$stage/common" "$stage/runtime" "$extract_parent"
  cp -a "$systems_root/$slug/." "$stage/"
  cp -a "$systems_root/common/." "$stage/common/"
  install -m 0644 "$systems_root/contract.toml" "$stage/contract.toml"
  install -m 0644 "$repo_root/LICENSE" "$stage/LICENSE"

  while IFS= read -r -d '' path; do
    sed -i "s/0[.]0[.]0/$version/g" "$path"
  done < <(find "$stage" -type f -print0)

  install -m 0755 "$repo_root/bin/sshfling" "$stage/runtime/sshfling.py"
  copy_sshfling_templates "$repo_root" "$stage/runtime/templates"

  (
    cd "$stage"
    find . -type f -print0 |
      sort -z |
      xargs -0 sha256sum
  ) >"$manifest"
  install -m 0644 "$manifest" "$stage/SOURCE-MANIFEST.sha256"
  find "$stage" -type f -printf '%P\n' | sort >"$expected_inventory"
  file_count="$(wc -l <"$expected_inventory" | tr -d ' ')"
  inventory_sha="$(sha256sum "$expected_inventory" | awk '{print $1}')"

  deterministic_tar_gz "$stage_parent" "$base_name" "$archive"
  deterministic_tar_gz "$stage_parent" "$base_name" "$repeat"
  cmp "$archive" "$repeat" >/dev/null

  tar -xzf "$archive" -C "$extract_parent"
  find "$extracted" -type f -printf '%P\n' | sort >"$extracted_inventory"
  cmp "$expected_inventory" "$extracted_inventory" >/dev/null
  (
    cd "$extracted"
    sha256sum -c SOURCE-MANIFEST.sha256 >/dev/null
  )
  test -s "$extracted/$metadata"
  archive_sha="$(sha256sum "$archive" | awk '{print $1}')"
  package_roots["$slug"]="$extracted"
  record_validation "$slug" source-archive PASS \
    "artifact=$(basename "$archive");sha256=$archive_sha;files=$file_count;inventory_sha256=$inventory_sha;repeat_build=identical"
  printf 'ARCHIVE\t%s\tPASS\tartifact=%s;sha256=%s;files=%s\n' \
    "$slug" "$(basename "$archive")" "$archive_sha" "$file_count"
}

selected_slug() {
  local slug="$1"
  ((${#requested[@]} == 0)) || [[ -n "${requested[$slug]:-}" ]]
}

canonical_system_slug() {
  case "$1" in
    Red) printf '%s\n' red ;;
    "Delphi/Object Pascal") printf '%s\n' object-pascal ;;
    *) printf '%s\n' "$1" ;;
  esac
}

canonical_system_language() {
  case "$1" in
    red) printf '%s\n' Red ;;
    object-pascal) printf '%s\n' "Delphi/Object Pascal" ;;
    *) printf '%s\n' "$2" ;;
  esac
}

validate_sources() {
  python3 - "$systems_root" <<'PY'
import csv
import json
import pathlib
import sys
import tomllib

root = pathlib.Path(sys.argv[1])
expected = {
    "assembly", "objective-c", "fortran", "cobol", "ada", "zig", "nim", "d",
    "object-pascal", "v", "crystal", "webassembly-wasi", "forth", "odin",
    "pony", "chapel", "harbour", "red", "swift",
}
rows = []
with (root / "packages.tsv").open(encoding="utf-8", newline="") as handle:
    for raw in handle:
        if raw.startswith("#") or not raw.strip():
            continue
        row = next(csv.reader([raw], delimiter="|"))
        if len(row) != 5:
            raise SystemExit(f"invalid registry row: {raw.rstrip()}")
        rows.append(row)

slugs = [row[0] for row in rows]
if set(slugs) != expected or len(slugs) != len(expected):
    raise SystemExit("systems-language registry must contain each expected slug exactly once")

contract = tomllib.loads((root / "contract.toml").read_text(encoding="utf-8"))
if contract.get("abi") != "sshfling-launcher-v1" or contract.get("exit_policy") != "child-exact":
    raise SystemExit("invalid launcher contract metadata")

for slug, language, toolchains, metadata, sources in rows:
    package = root / slug
    metadata_path = package / metadata
    if not metadata_path.is_file():
        raise SystemExit(f"{slug}: missing metadata {metadata}")
    for relative in sources.split(","):
        path = package / relative
        if not path.is_file() or path.stat().st_size == 0:
            raise SystemExit(f"{slug}: missing or empty source {relative}")

for path in root.glob("**/*.toml"):
    tomllib.loads(path.read_text(encoding="utf-8"))
for path in root.glob("**/*.json"):
    json.loads(path.read_text(encoding="utf-8"))

checks = {
    "objective-c/CMakeLists.txt": "project(SSHFlingObjectiveC",
    "zig/build.zig.zon": '.name = "sshfling"',
    "nim/sshfling.nimble": 'version = "0.0.0"',
    "v/v.mod": "name: 'sshfling'",
    "crystal/shard.yml": "name: sshfling",
    "webassembly-wasi/wit/sshfling.wit": "world sshfling",
    "harbour/sshfling.hbp": "src/sshfling.prg",
    "swift/Package.swift": "// swift-tools-version: 5.9",
}
for relative, marker in checks.items():
    if marker not in (root / relative).read_text(encoding="utf-8"):
        raise SystemExit(f"invalid package metadata marker in {relative}")
PY
}

declare -a inventory_tools=(
  gcc clang cc objcopy llvm-objcopy as ld
  gfortran flang-new flang fpc cobc gnatmake gprbuild zig nim nimble
  ldc2 dmd gdc v crystal wat2wasm wasm-ld wasmtime gforth odin ponyc
  node chpl mason harbour hbmk2 red swift swiftc
)

print_inventory() {
  local tool
  printf '%s\n' 'TOOLCHAIN INVENTORY'
  for tool in "${inventory_tools[@]}"; do
    if command -v "$tool" >/dev/null 2>&1; then
      printf 'FOUND  %-18s %s\n' "$tool" "$(command -v "$tool")"
      record_validation inventory "$tool" FOUND "path=$(command -v "$tool")"
    else
      printf 'MISSING %-18s\n' "$tool"
      record_validation inventory "$tool" MISSING "not-on-PATH"
    fi
  done

  local wasi_inventory_cc
  wasi_inventory_cc="$(find_wasi_cc || true)"
  if [[ -n "$wasi_inventory_cc" ]]; then
    printf 'WASM-TARGET wasm32-wasip1 compile=yes compiler=%s\n' "$wasi_inventory_cc"
  else
    printf '%s\n' 'WASM-TARGET wasm32-wasip1 compiler=missing'
  fi
  if command -v objcopy >/dev/null 2>&1 && objcopy --info 2>&1 | grep -Eqi 'wasm|webassembly'; then
    printf '%s\n' 'WASM-TARGET GNU-objcopy support=yes'
  else
    printf '%s\n' 'WASM-TARGET GNU-objcopy support=no'
  fi
}

first_command() {
  local candidate
  for candidate in "$@"; do
    if command -v "$candidate" >/dev/null 2>&1; then
      command -v "$candidate"
      return 0
    fi
  done
  return 1
}

SYSTEMS_CC=""
OBJC_CC=""
FORTRAN_CC=""
D_CC=""
WASI_CC="${WASI_CC:-}"
GATE_REASON=""

find_wasi_cc() {
  local candidate
  for candidate in "${WASI_CC:-}" sshfling-wasi-clang clang; do
    [[ -n "$candidate" ]] || continue
    if command -v "$candidate" >/dev/null 2>&1 &&
      printf 'int probe(void){return 0;}\n' |
        "$candidate" --target=wasm32-wasip1 -x c -c - -o "$work_root/wasi-cc-probe.o" \
          >/dev/null 2>&1; then
      command -v "$candidate"
      return 0
    fi
  done
  return 1
}

detect_language() {
  local slug="$1"
  local probe_dir="$work_root/probe-$slug"
  install -d "$probe_dir"
  GATE_REASON=""

  case "$slug" in
    assembly)
      if [[ "$(uname -m)" != "x86_64" ]]; then
        GATE_REASON="GNU x86_64 assembly source requires an x86_64 host"
        return 1
      fi
      SYSTEMS_CC="$(first_command gcc clang cc || true)"
      if [[ -z "$SYSTEMS_CC" ]]; then
        GATE_REASON="gcc or clang is required"
        return 1
      fi
      if ! command -v objcopy >/dev/null 2>&1; then
        GATE_REASON="GNU objcopy is required for binary-format validation"
        return 1
      fi
      if ! printf '.text\n.globl probe\nprobe: ret\n.section .note.GNU-stack,"",@progbits\n' |
        "$SYSTEMS_CC" -x assembler -c - -o "$probe_dir/probe.o" >/dev/null 2>&1; then
        GATE_REASON="$SYSTEMS_CC failed the x86_64 assembly compile probe"
        return 1
      fi
      if ! objcopy --only-keep-debug "$probe_dir/probe.o" "$probe_dir/probe.debug" >/dev/null 2>&1; then
        GATE_REASON="objcopy failed the ELF object probe"
        return 1
      fi
      ;;
    objective-c)
      local candidate
      for candidate in clang gcc; do
        if command -v "$candidate" >/dev/null 2>&1 &&
          printf '__attribute__((objc_root_class)) @interface P @end\n@implementation P @end\nint main(void){return 0;}\n' |
            "$candidate" -x objective-c - -lobjc -o "$probe_dir/probe" >/dev/null 2>&1; then
          OBJC_CC="$(command -v "$candidate")"
          return 0
        fi
      done
      GATE_REASON="no clang/GNU Objective-C frontend plus libobjc passed a compile/link probe"
      return 1
      ;;
    fortran)
      FORTRAN_CC="$(first_command gfortran flang-new flang || true)"
      if [[ -z "$FORTRAN_CC" ]]; then
        GATE_REASON="gfortran or flang is required"
        return 1
      fi
      if ! printf 'program p\nend program p\n' | "$FORTRAN_CC" -x f95 - -o "$probe_dir/probe" >/dev/null 2>&1; then
        GATE_REASON="$FORTRAN_CC failed the Fortran compile/link probe"
        return 1
      fi
      ;;
    object-pascal)
      command -v fpc >/dev/null 2>&1 || { GATE_REASON="Free Pascal fpc is required"; return 1; }
      install -d "$probe_dir/units"
      printf 'program probe;\nbegin\n  Halt(0);\nend.\n' >"$probe_dir/probe.pas"
      if ! fpc -Mobjfpc -Sh -FU"$probe_dir/units" -FE"$probe_dir" \
          -o"$probe_dir/probe" "$probe_dir/probe.pas" >/dev/null 2>&1; then
        GATE_REASON="Free Pascal failed the Object Pascal compile/link probe"
        return 1
      fi
      ;;
    cobol)
      command -v cobc >/dev/null 2>&1 || { GATE_REASON="GnuCOBOL cobc is required"; return 1; }
      ;;
    ada)
      command -v gnatmake >/dev/null 2>&1 || { GATE_REASON="GNAT gnatmake is required"; return 1; }
      ;;
    zig)
      command -v zig >/dev/null 2>&1 || { GATE_REASON="Zig is required"; return 1; }
      if ! zig build --build-file "${package_roots[zig]}/build.zig" \
          --prefix "$probe_dir/prefix" \
          --cache-dir "$probe_dir/cache" \
          --global-cache-dir "$probe_dir/global-cache" >/dev/null 2>&1; then
        GATE_REASON="installed Zig failed the tracked package build compatibility probe"
        return 1
      fi
      ;;
    nim)
      command -v nim >/dev/null 2>&1 || { GATE_REASON="Nim is required"; return 1; }
      command -v nimble >/dev/null 2>&1 || { GATE_REASON="Nimble is required for package metadata validation"; return 1; }
      ;;
    d)
      D_CC="$(first_command ldc2 dmd gdc || true)"
      [[ -n "$D_CC" ]] || { GATE_REASON="LDC, DMD, or GDC is required"; return 1; }
      command -v ar >/dev/null 2>&1 || { GATE_REASON="ar is required for D library validation"; return 1; }
      ;;
    v)
      command -v v >/dev/null 2>&1 || { GATE_REASON="V is required"; return 1; }
      ;;
    crystal)
      command -v crystal >/dev/null 2>&1 || { GATE_REASON="Crystal is required"; return 1; }
      ;;
    webassembly-wasi)
      local detected_wasi_cc
      detected_wasi_cc="$(find_wasi_cc || true)"
      if [[ -z "$detected_wasi_cc" ]]; then
        GATE_REASON="clang with wasm32-wasip1 support and a WASI sysroot is required"
        return 1
      fi
      WASI_CC="$detected_wasi_cc"
      command -v node >/dev/null 2>&1 || { GATE_REASON="Node.js with WASI Preview 1 support is required by the host adapter"; return 1; }
      if ! node -e 'require("node:wasi"); new WebAssembly.Module(Uint8Array.from([0,97,115,109,1,0,0,0]))' \
          >/dev/null 2>&1; then
        GATE_REASON="Node.js failed the WASI/WebAssembly runtime probe"
        return 1
      fi
      ;;
    forth)
      command -v gforth >/dev/null 2>&1 || { GATE_REASON="gforth is required"; return 1; }
      command -v sh >/dev/null 2>&1 || { GATE_REASON="a POSIX sh is required by the tested Gforth process backend"; return 1; }
      ;;
    odin)
      command -v odin >/dev/null 2>&1 || { GATE_REASON="Odin is required"; return 1; }
      ;;
    pony)
      command -v ponyc >/dev/null 2>&1 || { GATE_REASON="ponyc is required"; return 1; }
      ;;
    chapel)
      command -v chpl >/dev/null 2>&1 || { GATE_REASON="Chapel chpl is required"; return 1; }
      ;;
    harbour)
      command -v hbmk2 >/dev/null 2>&1 || { GATE_REASON="Harbour hbmk2 is required"; return 1; }
      ;;
    red)
      command -v red >/dev/null 2>&1 || { GATE_REASON="the Red compiler is required"; return 1; }
      if ! red -r -o "$probe_dir/probe" "${package_roots[red]}/src/main.reds" \
          >/dev/null 2>&1; then
        GATE_REASON="the red command is not a compatible Red/System compiler"
        return 1
      fi
      local red_cc
      red_cc="$(common_cc || true)"
      if [[ -z "$red_cc" ]]; then
        GATE_REASON="gcc or clang is required for the Red/System launcher ABI"
        return 1
      fi
      if ! printf 'int main(void){return 0;}\n' |
          "$red_cc" -m32 -x c - -o "$probe_dir/elf32-probe" >/dev/null 2>&1; then
        GATE_REASON="$red_cc with 32-bit multilib support is required for the Red/System launcher ABI"
        return 1
      fi
      ;;
    swift)
      command -v swift >/dev/null 2>&1 || { GATE_REASON="SwiftPM (swift) is required"; return 1; }
      command -v swiftc >/dev/null 2>&1 || { GATE_REASON="the Swift compiler (swiftc) is required"; return 1; }
      ;;
    *)
      GATE_REASON="unknown registry slug"
      return 1
      ;;
  esac
}

runtime_dir="$work_root/runtime"
install -d "$runtime_dir"
install -m 0755 "$repo_root/bin/sshfling" "$runtime_dir/sshfling.py"
copy_sshfling_templates "$repo_root" "$runtime_dir/templates"

common_cc() {
  if [[ -z "$SYSTEMS_CC" ]]; then
    SYSTEMS_CC="$(first_command gcc clang cc || true)"
  fi
  if [[ -z "$SYSTEMS_CC" ]]; then
    echo "a C compiler is required for the shared launcher ABI" >&2
    return 127
  fi
  printf '%s\n' "$SYSTEMS_CC"
}

compile_common_object() {
  local output="$1"
  local common_root="${2:-$systems_root/common}"
  local cc
  cc="$(common_cc)"
  "$cc" -std=c11 -Wall -Wextra -Wpedantic -Werror -fPIC \
    "$version_define" \
    -I"$common_root" \
    -c "$common_root/sshfling_launcher.c" -o "$output"
}

expect_status() {
  local expected="$1"
  shift
  local status
  set +e
  "$@" >"$work_root/status.stdout" 2>"$work_root/status.stderr"
  status=$?
  set -e
  if [[ "$status" -ne "$expected" ]]; then
    echo "expected exit $expected, received $status: $*" >&2
    return 1
  fi
}

expect_failure() {
  local status
  set +e
  "$@" >"$work_root/failure.stdout" 2>"$work_root/failure.stderr"
  status=$?
  set -e
  if [[ "$status" -eq 0 ]]; then
    echo "expected failure, received exit 0: $*" >&2
    return 1
  fi
}

install_source_package() {
  local slug="$1"
  local prefix="$2"
  rm -rf -- "$prefix"
  install -d "$prefix"
  cp -a "${package_roots[$slug]}/." "$prefix/"
  record_validation "$slug" install PASS "isolated_prefix=$prefix;source_archive_extracted=yes"
}

test_package_removal() {
  local slug="$1"
  local prefix="$2"
  local cli="$3"
  shift 3
  rm -rf -- "$prefix"
  test ! -e "$prefix"
  test ! -e "$cli"
  local marker
  for marker in "$@"; do
    test ! -e "$marker"
  done
  expect_status 127 "$cli" --version
  record_validation "$slug" uninstall PASS \
    "isolated_prefix_removed=yes;cli_execution_after_removal=127;library_paths_absent=yes"
}

test_native_cli() {
  local binary="$1"
  local slug="${2:-native}"
  local package_runtime="${3:-$runtime_dir}"
  local output
  local smoke_dir
  output="$(SSHFLING_RUNTIME_DIR="$package_runtime" "$binary" --version)"
  [[ "$output" == "sshfling $version" ]]
  record_validation "$slug" cli-version PASS "output=$output"
  smoke_dir="$(dirname "$binary")/template smoke's"
  SSHFLING_RUNTIME_DIR="$package_runtime" "$binary" init "$smoke_dir" \
    --force --session-seconds 60 >/dev/null
  test -x "$smoke_dir/native/sshfling-linux-account"
  test -x "$smoke_dir/native/sshfling-unix-identity"
  test -x "$smoke_dir/production/sshfling-login-shell"
  test -f "$smoke_dir/README.md"
  test -f "$smoke_dir/compose.server.yml"
  grep -Fqx 'SSH_SESSION_SECONDS=60' "$smoke_dir/.env"
  record_validation "$slug" init-template PASS \
    "session_seconds=60;native_and_production_executables=yes;project_assets=yes"
  expect_status 2 env SSHFLING_RUNTIME_DIR="$package_runtime" "$binary" --not-a-real-option
  record_validation "$slug" invalid-option PASS "exit=2"
  expect_status 127 env SSHFLING_RUNTIME_DIR="$work_root/missing-runtime" "$binary" --version
  record_validation "$slug" missing-runtime PASS "exit=127"
}

build_assembly() {
  local out="$1"
  local cc="$SYSTEMS_CC"
  compile_common_object "$out/launcher.o"
  "$cc" -Wall -Wextra -Werror -fPIC -c "$systems_root/assembly/src/sshfling.S" -o "$out/assembly.o"
  "$cc" -shared "$out/launcher.o" "$out/assembly.o" -o "$out/libsshfling_assembly.so"
  "$cc" -Wall -Wextra -Werror "$systems_root/assembly/src/main.S" \
    -L"$out" -lsshfling_assembly -Wl,-rpath,"$out" -o "$out/sshfling-assembly"
  objcopy --only-keep-debug "$out/sshfling-assembly" "$out/sshfling-assembly.debug"
  test -s "$out/sshfling-assembly.debug"
  printf '#include <stddef.h>\n#include <string.h>\nextern const char *sshfling_assembly_version(void);\nextern int sshfling_assembly_run(size_t,const char *const[]);\nint main(int c,char **v){const char *a[]={"--version"};return c==2&&strcmp(sshfling_assembly_version(),v[1])==0?sshfling_assembly_run(1,a):1;}\n' |
    "$cc" -Wall -Wextra -Werror -x c - -L"$out" -lsshfling_assembly -Wl,-rpath,"$out" -o "$out/library-test"
  SSHFLING_RUNTIME_DIR="$runtime_dir" "$out/library-test" "$version" | grep -Fx "sshfling $version" >/dev/null
  test_native_cli "$out/sshfling-assembly" assembly
}

build_objective_c() {
  local out="$1"
  compile_common_object "$out/launcher.o"
  "$OBJC_CC" -Wall -Wextra -Werror -fPIC -I"$systems_root/common" \
    -I"$systems_root/objective-c/include" -c "$systems_root/objective-c/src/SSHFling.m" -o "$out/objc.o"
  "$OBJC_CC" -shared "$out/launcher.o" "$out/objc.o" -lobjc -o "$out/libsshfling_objc.so"
  "$OBJC_CC" -Wall -Wextra -Werror -I"$systems_root/objective-c/include" \
    -c "$systems_root/objective-c/src/main.m" -o "$out/main.o"
  "$OBJC_CC" "$out/main.o" -L"$out" -lsshfling_objc -lobjc -Wl,-rpath,"$out" -o "$out/sshfling-objective-c"
  printf '#import <SSHFling/SSHFling.h>\n#include <string.h>\nint main(int c,char **v){const char *a[]={"--version"};return c==2&&strcmp([SSHFling version],v[1])==0?[SSHFling runWithArgumentCount:1 arguments:a]:1;}\n' |
    "$OBJC_CC" -x objective-c -Wall -Wextra -Werror -I"$systems_root/objective-c/include" -c - -o "$out/consumer.o"
  "$OBJC_CC" "$out/consumer.o" -L"$out" -lsshfling_objc -lobjc -Wl,-rpath,"$out" -o "$out/consumer"
  SSHFLING_RUNTIME_DIR="$runtime_dir" "$out/consumer" "$version" | grep -Fx "sshfling $version" >/dev/null
  test_native_cli "$out/sshfling-objective-c" objective-c
}

build_fortran() {
  local out="$1"
  compile_common_object "$out/launcher.o"
  "$FORTRAN_CC" -std=f2018 -Wall -Wextra -Werror -fPIC -J"$out" \
    -c "$systems_root/fortran/src/sshfling.f90" -o "$out/sshfling.o"
  "$FORTRAN_CC" -std=f2018 -Wall -Wextra -Werror -I"$out" \
    "$systems_root/fortran/app/main.f90" "$out/sshfling.o" "$out/launcher.o" -o "$out/sshfling-fortran"
  test_native_cli "$out/sshfling-fortran" fortran
}

build_object_pascal() {
  local out="$1"
  local package="${package_roots[object-pascal]}"
  local consumer="$out/sshfling-object-pascal-consumer"
  local output
  install -d "$out/cli-units" "$out/consumer-units"
  fpc -Mobjfpc -Sh -Fu"$package/src" -FU"$out/cli-units" \
    -FE"$out" -o"$out/sshfling-object-pascal" "$package/app/main.pas" >/dev/null
  fpc -Mobjfpc -Sh -Fu"$package/src" -FU"$out/consumer-units" \
    -FE"$out" -o"$consumer" "$package/consumers/main.pas" >/dev/null
  output="$(SSHFLING_RUNTIME_DIR="$runtime_dir" "$consumer")"
  [[ "$output" == "sshfling $version" ]]
  record_validation object-pascal isolated-consumer PASS \
    "unit=SSHFling;compiler=fpc;output=$output"
  test_native_cli "$out/sshfling-object-pascal" object-pascal
}

build_cobol() {
  local out="$1"
  compile_common_object "$out/launcher.o"
  cobc -free -Wall -Wextra -Werror -Wno-unfinished -c \
    "$systems_root/cobol/src/sshfling.cob" -o "$out/sshfling_cobol.o"
  cobc -free -Wall -Wextra -Werror -Wno-unfinished -x \
    "$systems_root/cobol/app/main.cob" "$out/sshfling_cobol.o" "$out/launcher.o" -o "$out/sshfling-cobol"
  test_native_cli "$out/sshfling-cobol" cobol
}

build_ada() {
  local out="$1"
  install -d "$out/obj"
  compile_common_object "$out/launcher.o"
  gnatmake -q -gnat2022 -gnatwa -gnatwe -D "$out/obj" \
    -I"$systems_root/ada/src" -I"$systems_root/ada/app" \
    "$systems_root/ada/app/sshfling_main.adb" -o "$out/sshfling-ada" -largs "$out/launcher.o"
  test_native_cli "$out/sshfling-ada" ada
}

build_zig() {
  local out="$1"
  zig build --build-file "${package_roots[zig]}/build.zig" --prefix "$out/prefix" \
    --cache-dir "$out/cache" --global-cache-dir "$out/global-cache"
  test_native_cli "$out/prefix/bin/sshfling-zig" zig
}

build_nim() {
  local out="$1"
  local source_root="$out/source"
  local nim_version_define="-DSSHFLING_VERSION=\\\"$version\\\""
  install -d "$out/home" "$out/nimcache" "$source_root/common"
  cp -a "$systems_root/nim/." "$source_root/"
  cp -a "$systems_root/common/." "$source_root/common/"
  HOME="$out/home" nim check --hints:off --warnings:off --path:"$source_root/src" \
    "$source_root/src/sshfling_cli.nim"
  HOME="$out/home" nim c --hints:off --warnings:off --nimcache:"$out/nimcache" \
    --path:"$source_root/src" --passC:"$nim_version_define" --out:"$out/sshfling-nim" \
    "$source_root/src/sshfling_cli.nim"
  (cd "$source_root" && HOME="$out/home" nimble check >/dev/null)
  test_native_cli "$out/sshfling-nim" nim
}

build_d() {
  local out="$1"
  local compiler_name
  compiler_name="$(basename "$D_CC")"
  compile_common_object "$out/launcher.o"
  case "$compiler_name" in
    ldc2|dmd)
      "$D_CC" -w -c "$systems_root/d/source/sshfling.d" -of="$out/sshfling_d.o"
      ar rcs "$out/libsshfling_d.a" "$out/sshfling_d.o" "$out/launcher.o"
      "$D_CC" -w -I="$systems_root/d/source" "$systems_root/d/app/main.d" \
        -L-L"$out" -L-lsshfling_d -of="$out/sshfling-d"
      ;;
    gdc)
      "$D_CC" -Wall -Wextra -Werror -c "$systems_root/d/source/sshfling.d" -o "$out/sshfling_d.o"
      ar rcs "$out/libsshfling_d.a" "$out/sshfling_d.o" "$out/launcher.o"
      "$D_CC" -I"$systems_root/d/source" "$systems_root/d/app/main.d" \
        -L"$out" -lsshfling_d -o "$out/sshfling-d"
      ;;
  esac
  test_native_cli "$out/sshfling-d" d
}

build_v() {
  local out="$1"
  local prefix="$out/install"
  local consumer_root="$out/consumer"
  local cli="$prefix/bin/sshfling-v"
  local consumer="$consumer_root/sshfling-v-consumer"
  local output
  install_source_package v "$prefix"
  install -d "$prefix/bin" "$consumer_root"
  cp -a "$prefix/consumers/." "$consumer_root/"
  (
    cd "$prefix"
    v -o "$cli" cmd/sshfling
  )
  v -path "$prefix|@vlib" -o "$consumer" "$consumer_root/main.v"
  output="$(SSHFLING_RUNTIME_DIR="$prefix/runtime" "$consumer" "$version")"
  [[ "$output" == "sshfling $version" ]]
  record_validation v isolated-consumer PASS \
    "import=sshfling;package_version=$version;runtime_version=$version;output=$output"
  test_native_cli "$cli" v "$prefix/runtime"
  test_package_removal v "$prefix" "$cli" "$prefix/sshfling/sshfling.v"
  expect_failure v -path "$prefix|@vlib" \
    -o "$out/post-remove-consumer" "$consumer_root/main.v"
  record_validation v uninstall-import PASS "import_fails_after_removal=yes"
}

build_crystal() {
  local out="$1"
  local cc
  install -d "$out/home" "$out/crystal-cache"
  cc="$(common_cc)"
  "$cc" -std=c11 -Wall -Wextra -Wpedantic -Werror -fPIC "$version_define" \
    -I"$systems_root/common" -shared "$systems_root/common/sshfling_launcher.c" -o "$out/libsshfling_launcher.so"
  HOME="$out/home" CRYSTAL_CACHE_DIR="$out/crystal-cache" LIBRARY_PATH="$out" \
    crystal build "$systems_root/crystal/src/cli.cr" -o "$out/sshfling-crystal"
  LD_LIBRARY_PATH="$out${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    test_native_cli "$out/sshfling-crystal" crystal
}

build_webassembly_wasi() {
  local out="$1"
  local prefix="$out/install"
  local consumer_root="$out/consumer"
  local cli="$prefix/bin/sshfling-wasi.mjs"
  local module="$prefix/lib/sshfling-wasi.wasm"
  local output
  install_source_package webassembly-wasi "$prefix"
  install -d "$prefix/lib" "$consumer_root"
  cp -a "$prefix/consumers/node/." "$consumer_root/"
  "$WASI_CC" --target=wasm32-wasip1 -O2 -Wall -Wextra -Werror \
    -Wl,--export=sshfling_wasi_version \
    -Wl,--export=sshfling_wasi_run \
    "$prefix/src/main.c" -o "$module"
  chmod 0755 "$cli"
  output="$(SSHFLING_RUNTIME_DIR="$prefix/runtime" \
    node "$consumer_root/main.mjs" "$prefix" "$version")"
  [[ "$output" == "sshfling $version" ]]
  record_validation webassembly-wasi isolated-consumer PASS \
    "api=host-adapter+wasm-exports;package_version=$version;module_version=$version;output=$output"
  test_native_cli "$cli" webassembly-wasi "$prefix/runtime"
  test_package_removal webassembly-wasi "$prefix" "$cli" "$module"
  expect_failure node "$consumer_root/main.mjs" "$prefix" "$version"
  record_validation webassembly-wasi uninstall-import PASS \
    "host_api_and_wasm_module_unavailable_after_removal=yes"
}

build_forth() {
  local out="$1"
  local bridge="$out/libsshfling_gforth.so"
  local cc
  local output
  local smoke_dir="$out/template smoke's"
  install -d "$out/home"
  compile_common_object "$out/launcher.o"
  cc="$(common_cc)"
  "$cc" -Wall -Wextra -Werror -fPIC "$version_define" \
    -I"$systems_root/common" \
    -c "$systems_root/forth/bridge.c" -o "$out/bridge.o"
  "$cc" -shared "$out/launcher.o" "$out/bridge.o" -o "$bridge"
  (cd "$systems_root/forth" && HOME="$out/home" SSHFLING_FORTH_BRIDGE="$bridge" gforth sshfling.fs \
    -e 'sshfling-version type cr bye') | grep -Fx "$version" >/dev/null
  output="$(cd "$systems_root/forth" && HOME="$out/home" SSHFLING_RUNTIME_DIR="$runtime_dir" SSHFLING_FORTH_BRIDGE="$bridge" gforth cli.fs --version)"
  [[ "$output" == "sshfling $version" ]]
  record_validation forth cli-version PASS "output=$output"
  (
    cd "$systems_root/forth"
    HOME="$out/home" SSHFLING_RUNTIME_DIR="$runtime_dir" SSHFLING_FORTH_BRIDGE="$bridge" \
      gforth cli.fs init "$smoke_dir" --force --session-seconds 60 >/dev/null
  )
  test -x "$smoke_dir/native/sshfling-linux-account"
  test -x "$smoke_dir/native/sshfling-unix-identity"
  test -x "$smoke_dir/production/sshfling-login-shell"
  record_validation forth init-template PASS \
    "native_and_production_executables=yes"
  # $1 is intentionally expanded by the nested shell.
  # shellcheck disable=SC2016
  expect_status 2 env HOME="$out/home" SSHFLING_RUNTIME_DIR="$runtime_dir" \
    SSHFLING_FORTH_BRIDGE="$bridge" \
    bash -c 'cd "$1" && exec gforth cli.fs --not-a-real-option' _ "$systems_root/forth"
  record_validation forth invalid-option PASS "exit=2"
  # shellcheck disable=SC2016
  expect_status 127 env HOME="$out/home" SSHFLING_RUNTIME_DIR="$work_root/missing-runtime" \
    SSHFLING_FORTH_BRIDGE="$bridge" \
    bash -c 'cd "$1" && exec gforth cli.fs --version' _ "$systems_root/forth"
  record_validation forth missing-runtime PASS "exit=127"
}

build_odin() {
  local out="$1"
  local prefix="$out/install"
  local consumer_root="$out/consumer"
  local cli="$prefix/bin/sshfling-odin"
  local consumer="$consumer_root/sshfling-odin-consumer"
  local output
  local cc
  install_source_package odin "$prefix"
  install -d "$prefix/bin" "$prefix/lib" "$consumer_root"
  cp -a "$prefix/consumers/." "$consumer_root/"
  cc="$(common_cc)"
  "$cc" -std=c11 -fPIC "$version_define" -I"$prefix/common" \
    -shared "$prefix/common/sshfling_launcher.c" -o "$prefix/lib/libsshfling_launcher.so"
  odin build "$prefix/cmd/sshfling" -collection:sshfling="$prefix" -out:"$cli" \
    -extra-linker-flags:"-L$prefix/lib -lsshfling_launcher"
  odin build "$consumer_root" -collection:sshfling="$prefix" -out:"$consumer" \
    -extra-linker-flags:"-L$prefix/lib -lsshfling_launcher"
  output="$(LD_LIBRARY_PATH="$prefix/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    SSHFLING_RUNTIME_DIR="$prefix/runtime" "$consumer" "$version")"
  [[ "$output" == "sshfling $version" ]]
  record_validation odin isolated-consumer PASS \
    "collection=sshfling;package_version=$version;runtime_version=$version;output=$output"
  LD_LIBRARY_PATH="$prefix/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    test_native_cli "$cli" odin "$prefix/runtime"
  test_package_removal odin "$prefix" "$cli" "$prefix/sshfling/sshfling.odin"
  expect_failure odin build "$consumer_root" -collection:sshfling="$prefix" \
    -out:"$out/post-remove-consumer"
  record_validation odin uninstall-import PASS "collection_import_fails_after_removal=yes"
}

build_pony() {
  local out="$1"
  local prefix="$out/install"
  local consumer_root="$out/consumer"
  local cli="$prefix/bin/sshfling-pony"
  local consumer="$consumer_root/sshfling-pony-consumer"
  local output
  local cc
  install_source_package pony "$prefix"
  install -d "$prefix/bin" "$prefix/lib" "$consumer_root"
  cp -a "$prefix/consumers/." "$consumer_root/"
  cc="$(common_cc)"
  "$cc" -std=c11 -Wall -Wextra -Wpedantic -Werror "$version_define" \
    -I"$prefix/common" -c "$prefix/common/sshfling_launcher.c" \
    -o "$out/sshfling_launcher.o"
  ar rcs "$prefix/lib/libsshfling_launcher.a" "$out/sshfling_launcher.o"
  ponyc "$prefix" -o "$out" -b pony -p "$prefix/lib"
  install -m 0755 "$out/pony" "$cli"
  ponyc "$consumer_root" -o "$consumer_root" -b consumer \
    -p "$prefix" -p "$prefix/lib"
  mv "$consumer_root/consumer" "$consumer"
  output="$(SSHFLING_RUNTIME_DIR="$prefix/runtime" "$consumer" "$version")"
  [[ "$output" == "sshfling $version" ]]
  record_validation pony isolated-consumer PASS \
    "package=sshfling;package_version=$version;runtime_version=$version;output=$output"
  test_native_cli "$cli" pony "$prefix/runtime"
  test_package_removal pony "$prefix" "$cli" "$prefix/sshfling/sshfling.pony"
  expect_failure ponyc "$consumer_root" -o "$out/post-remove" -p "$prefix"
  record_validation pony uninstall-import PASS "package_import_fails_after_removal=yes"
}

build_chapel() {
  local out="$1"
  local prefix="$out/install"
  local consumer_root="$out/consumer"
  local cli="$prefix/bin/sshfling-chapel"
  local consumer="$consumer_root/sshfling-chapel-consumer"
  local output
  install_source_package chapel "$prefix"
  install -d "$prefix/bin" "$prefix/lib/chapel" "$consumer_root"
  install -m 0644 "$prefix/src/SSHFling.chpl" "$prefix/lib/chapel/SSHFling.chpl"
  cp -a "$prefix/consumers/." "$consumer_root/"
  compile_common_object "$out/launcher.o" "$prefix/common"
  if command -v mason >/dev/null 2>&1; then
    (cd "$prefix" && mason modules >/dev/null)
    record_validation chapel package-metadata PASS "mason_modules=yes"
  fi
  chpl --ccflags "-I$prefix/common" "$prefix/lib/chapel/SSHFling.chpl" "$prefix/src/main.chpl" \
    "$out/launcher.o" -o "$cli"
  chpl --ccflags "-I$prefix/common" "$prefix/lib/chapel/SSHFling.chpl" "$consumer_root/main.chpl" \
    "$out/launcher.o" -o "$consumer"
  output="$(SSHFLING_RUNTIME_DIR="$prefix/runtime" "$consumer" "$version")"
  [[ "$output" == "sshfling $version" ]]
  record_validation chapel isolated-consumer PASS \
    "module=SSHFling;package_version=$version;runtime_version=$version;output=$output"
  test_native_cli "$cli" chapel "$prefix/runtime"
  test_package_removal chapel "$prefix" "$cli" "$prefix/lib/chapel/SSHFling.chpl"
  expect_failure chpl --ccflags "-I$prefix/common" "$prefix/lib/chapel/SSHFling.chpl" "$consumer_root/main.chpl" \
    "$out/launcher.o" -o "$out/post-remove-consumer"
  record_validation chapel uninstall-import PASS "module_compile_fails_after_removal=yes"
}

build_harbour() {
  local out="$1"
  local prefix="$out/install"
  install_source_package harbour "$prefix"
  (cd "$prefix" && hbmk2 sshfling.hbp -o"$out/sshfling-harbour")
  test_native_cli "$out/sshfling-harbour" harbour
}

build_red() {
  local out="$1"
  local cc
  local package="${package_roots[red]}"
  cc="$(common_cc)"
  "$cc" -m32 -std=c11 -fPIC "$version_define" -I"$package/common" \
    -shared "$package/common/sshfling_launcher.c" -o "$out/libsshfling_launcher.so"
  red -r -o "$out/sshfling-red" "$package/src/main.reds"
  LD_LIBRARY_PATH="$out${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    test_native_cli "$out/sshfling-red" red
}

build_swift() {
  local out="$1"
  local prefix="$out/install"
  local consumer_root="$out/consumer"
  local cli="$prefix/bin/sshfling-swift"
  local binary
  local output
  install_source_package swift "$prefix"
  install -d "$prefix/bin"
  cp -a "$prefix/Consumers/SSHFlingConsumer" "$consumer_root"
  swift package --package-path "$prefix" dump-package >/dev/null
  swift build --package-path "$prefix" --scratch-path "$out/scratch" -c release \
    -Xcc "$version_define"
  binary="$(swift build --package-path "$prefix" --scratch-path "$out/scratch" \
    -c release --show-bin-path)/sshfling-swift"
  install -m 0755 "$binary" "$cli"
  output="$(SSHFLING_RUNTIME_DIR="$prefix/runtime" \
    swift run --package-path "$consumer_root" --scratch-path "$out/consumer-scratch" \
      -c release SSHFlingConsumer "$version")"
  [[ "$output" == "sshfling $version" ]]
  record_validation swift isolated-consumer PASS \
    "swiftpm_local_dependency=yes;package_version=$version;runtime_version=$version;output=$output"
  test_native_cli "$cli" swift "$prefix/runtime"
  test_package_removal swift "$prefix" "$cli" "$prefix/Sources/SSHFling/SSHFling.swift"
  expect_failure swift build --package-path "$consumer_root" \
    --scratch-path "$out/post-remove-scratch" -c release
  record_validation swift uninstall-import PASS "swiftpm_dependency_fails_after_removal=yes"
}

build_language() {
  local slug="$1"
  local out="$work_root/build-$slug"
  install -d "$out"
  case "$slug" in
    assembly) build_assembly "$out" ;;
    objective-c) build_objective_c "$out" ;;
    fortran) build_fortran "$out" ;;
    object-pascal) build_object_pascal "$out" ;;
    cobol) build_cobol "$out" ;;
    ada) build_ada "$out" ;;
    zig) build_zig "$out" ;;
    nim) build_nim "$out" ;;
    d) build_d "$out" ;;
    v) build_v "$out" ;;
    crystal) build_crystal "$out" ;;
    webassembly-wasi) build_webassembly_wasi "$out" ;;
    forth) build_forth "$out" ;;
    odin) build_odin "$out" ;;
    pony) build_pony "$out" ;;
    chapel) build_chapel "$out" ;;
    harbour) build_harbour "$out" ;;
    red) build_red "$out" ;;
    swift) build_swift "$out" ;;
  esac
}

print_inventory
printf '%s\n' 'SOURCE VALIDATION'
validate_sources
printf '%s\n' 'VALIDATED metadata/source registry (19 packages)'
record_validation batch source-registry PASS "packages=19;metadata_and_declared_sources=validated"

if ((${#requested[@]} > 0)); then
  while IFS= read -r slug; do
    if ! awk -F '|' -v wanted="$slug" '$1 == wanted {found=1} END {exit !found}' "$registry"; then
      echo "Unknown systems-language slug: $slug" >&2
      exit 2
    fi
  done < <(printf '%s\n' "${!requested[@]}")
fi

printf '%s\n' 'SOURCE ARCHIVE VALIDATION'
while IFS='|' read -r slug _language _toolchains metadata _sources; do
  [[ "$slug" == \#* || -z "$slug" ]] && continue
  selected_slug "$slug" || continue
  create_source_archive "$slug" "$metadata"
done <"$registry"

tested=0
gated=0
failed=0
declare -a tested_languages=()
declare -a gated_languages=()
declare -a failed_languages=()

printf '%s\n' 'BUILD AND RUNTIME VALIDATION'
while IFS='|' read -r slug language _toolchains _metadata _sources; do
  [[ "$slug" == \#* || -z "$slug" ]] && continue
  slug="$(canonical_system_slug "$slug")"
  language="$(canonical_system_language "$slug" "$language")"
  selected_slug "$slug" || continue

  if ! detect_language "$slug"; then
    printf 'RUNTIME\t%s\tBLOCKED\treason=%s\n' "$slug" "$GATE_REASON"
    record_validation "$slug" runtime-validation BLOCKED "reason=$GATE_REASON"
    gated=$((gated + 1))
    gated_languages+=("$language")
    rm -rf -- "$work_root/probe-$slug"
    continue
  fi

  log="$work_root/$slug.log"
  builder_status=0
  set +e
  (
    set -Eeuo pipefail
    build_language "$slug"
  ) >"$log" 2>&1
  builder_status=$?
  set -e
  if ((builder_status == 0)); then
    validation_detail="$(runtime_validation_detail "$slug")"
    printf 'RUNTIME\t%s\tPASS\t%s\n' "$slug" "$validation_detail"
    record_validation "$slug" runtime-validation PASS "$validation_detail"
    tested=$((tested + 1))
    tested_languages+=("$language")
  else
    printf 'RUNTIME\t%s\tFAIL\tbuilder_exit=%d\n' "$slug" "$builder_status"
    sed -n '1,80p' "$log" >&2
    record_validation "$slug" runtime-validation FAIL \
      "builder_exit=$builder_status;log_sha256=$(sha256sum "$log" | awk '{print $1}')"
    failed=$((failed + 1))
    failed_languages+=("$language")
  fi
  rm -rf -- "$work_root/build-$slug" "$work_root/probe-$slug"
done <"$registry"

printf 'SUMMARY tested=%d blocked=%d failed=%d\n' "$tested" "$gated" "$failed"
printf 'TESTED_LANGUAGES=%s\n' "$(IFS=,; echo "${tested_languages[*]:-none}")"
printf 'BLOCKED_LANGUAGES=%s\n' "$(IFS=,; echo "${gated_languages[*]:-none}")"
printf 'FAILED_LANGUAGES=%s\n' "$(IFS=,; echo "${failed_languages[*]:-none}")"
record_validation batch summary "$([[ "$failed" -eq 0 && "$gated" -eq 0 ]] && echo PASS || echo INCOMPLETE)" \
  "tested=$tested;blocked=$gated;failed=$failed;allow_blocked=$allow_blocked"
printf 'EVIDENCE=%s\n' "$evidence_path"

if ((failed > 0)); then
  exit 1
fi
if ((gated > 0 && allow_blocked == 0)); then
  echo "FAIL-CLOSED: one or more selected toolchains were not runtime validated." >&2
  exit 78
fi
