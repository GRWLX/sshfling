#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
domain_root="$repo_root/packaging/domain-languages"
manifest="$domain_root/manifest.tsv"
blocker_doc="$repo_root/docs/language-external-blockers.md"

expected_slugs=(
  sql plsql tsql hcl-terraform solidity vyper move verilog vhdl
  systemverilog cuda opencl-c glsl hlsl wgsl matlab sas abap apex
  labview-g scratch wolfram-language power-query-m qsharp arduino-wiring
  micropython circuitpython autohotkey autoit applescript vbscript xojo
  delphi-object-pascal
)

usage() {
  cat <<'USAGE'
Usage: packaging/build-domain-languages.sh ACTION [LANGUAGE]

Actions:
  audit              Validate the complete inventory, quarantine, and docs.
  status             Report candidate validators available on this host.
  gate LANGUAGE      Run one candidate's focused conformance gate.
  gate-candidates    Gate every candidate; missing tools fail closed.
  gate-all           Gate every row; blocked rows necessarily fail closed.
  package LANGUAGE   Refuse release packaging while the row is unsupported.

Tool overrides:
  MATLAB, WOLFRAMSCRIPT, AUTOHOTKEY, AUTOIT, OSASCRIPT, OSACOMPILE,
  CSCRIPT, and FPC may name the corresponding executable.
USAGE
}

fail() {
  printf 'domain-language gate: %s\n' "$*" >&2
  return 1
}

manifest_row() {
  local requested="$1"
  awk -F '\t' -v requested="$requested" \
    'NR > 1 && $1 == requested { print; found = 1 } END { if (!found) exit 1 }' \
    "$manifest"
}

tool_for_slug() {
  case "$1" in
    matlab) printf '%s\n' "${MATLAB:-matlab}" ;;
    wolfram-language) printf '%s\n' "${WOLFRAMSCRIPT:-wolframscript}" ;;
    autohotkey) printf '%s\n' "${AUTOHOTKEY:-AutoHotkey64.exe}" ;;
    autoit) printf '%s\n' "${AUTOIT:-AutoIt3.exe}" ;;
    applescript) printf '%s\n' "${OSASCRIPT:-osascript}" ;;
    vbscript) printf '%s\n' "${CSCRIPT:-cscript.exe}" ;;
    delphi-object-pascal) printf '%s\n' "${FPC:-fpc}" ;;
    *) printf '%s\n' '-' ;;
  esac
}

require_tool() {
  local tool="$1"
  local language="$2"
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf '%s\n' \
      "$language gate is blocked: required validator '$tool' is not installed." \
      "See docs/language-external-blockers.md for platform and license prerequisites." >&2
    return 127
  fi
}

audit_manifest() {
  local expected_header=$'slug\tlanguage\tdisposition\tsurface\tvalidator'
  local actual_header
  local count=0
  local slug language disposition surface validator
  local seen_slugs=$'\n'

  [[ -r "$manifest" ]] || fail "missing manifest: $manifest"
  actual_header="$(sed -n '1p' "$manifest")"
  [[ "$actual_header" == "$expected_header" ]] || fail "invalid manifest header"

  while IFS=$'\t' read -r slug language disposition surface validator; do
    [[ -n "$slug" && -n "$language" ]] || fail "manifest contains an empty identity"
    [[ "$seen_slugs" != *$'\n'"$slug"$'\n'* ]] || \
      fail "duplicate manifest slug: $slug"
    seen_slugs+="$slug"$'\n'
    count=$((count + 1))

    case "$disposition" in
      candidate)
        [[ "$surface" != '-' && "$validator" != '-' ]] || \
          fail "$language candidate lacks a source or validator"
        [[ -f "$domain_root/$surface" ]] || \
          fail "$language candidate source is missing: $surface"
        ;;
      blocked)
        [[ "$surface" == '-' && "$validator" == '-' ]] || \
          fail "$language blocker must not masquerade as a source surface"
        ;;
      *) fail "$language has invalid disposition: $disposition" ;;
    esac

    grep -Fq "<!-- target:$slug -->" "$blocker_doc" || \
      fail "$language has no precise blocker-doc entry"
  done < <(tail -n +2 "$manifest")

  [[ "$count" -eq "${#expected_slugs[@]}" ]] || \
    fail "expected ${#expected_slugs[@]} targets, found $count"
  for slug in "${expected_slugs[@]}"; do
    [[ "$seen_slugs" == *$'\n'"$slug"$'\n'* ]] || \
      fail "manifest target is missing: $slug"
  done

  [[ -f "$domain_root/README.md" ]] || fail "domain-language README is missing"
  grep -Fq "The \`package\` action intentionally fails" "$domain_root/README.md" || \
    fail "README does not state the fail-closed package policy"
  grep -Fq "remain non-PASS" "$blocker_doc" || \
    fail "blocker doc does not preserve non-PASS status"

  if command -v shellcheck >/dev/null 2>&1; then
    shellcheck "$repo_root/packaging/build-domain-languages.sh" \
      "$domain_root/fixtures/fake-sshfling.sh"
  fi

  printf 'Audited %d domain-language rows: inventory complete; release packaging disabled.\n' "$count"
}

status_report() {
  local slug language disposition surface validator tool availability
  printf 'slug\tdisposition\tlocal-validator\n'
  while IFS=$'\t' read -r slug language disposition surface validator; do
    if [[ "$disposition" == 'blocked' ]]; then
      availability='blocked-by-design'
    else
      tool="$(tool_for_slug "$slug")"
      if command -v "$tool" >/dev/null 2>&1; then
        availability="available:$tool"
      else
        availability="missing:$tool"
      fi
    fi
    printf '%s\t%s\t%s\n' "$slug" "$disposition" "$availability"
  done < <(tail -n +2 "$manifest")
}

prepare_fake_executable() {
  local temp_root="$1"
  local fake_dir="$temp_root/fake executable"
  install -d -m 0755 "$fake_dir"
  install -m 0755 "$domain_root/fixtures/fake-sshfling.sh" \
    "$fake_dir/sshfling fake"
  printf '%s\n' "$fake_dir/sshfling fake"
}

gate_candidate() {
  local slug="$1"
  local temp_root="$2"
  local fake_executable="$3"
  local tool source_root escaped_root status

  tool="$(tool_for_slug "$slug")"
  case "$slug" in
    matlab)
      require_tool "$tool" 'MATLAB' || return
      source_root="$domain_root/matlab"
      escaped_root="${source_root//\'/\'\'}"
      SSHFLING_TEST_EXECUTABLE="$fake_executable" \
        "$tool" -batch "addpath('$escaped_root'); test_launcher"
      ;;
    wolfram-language)
      require_tool "$tool" 'Wolfram Language' || return
      SSHFLING_TEST_EXECUTABLE="$fake_executable" \
        "$tool" -file "$domain_root/wolfram-language/test_launcher.wls"
      ;;
    autohotkey)
      require_tool "$tool" 'AutoHotkey' || return
      "$tool" /ErrorStdOut "$domain_root/autohotkey/sshfling.ahk" --self-test
      ;;
    autoit)
      require_tool "$tool" 'AutoIt' || return
      "$tool" /ErrorStdOut "$domain_root/autoit/sshfling.au3" --self-test
      ;;
    applescript)
      require_tool "${OSACOMPILE:-osacompile}" 'AppleScript compiler' || return
      require_tool "$tool" 'AppleScript runtime' || return
      SSHFLING_TEST_EXECUTABLE="$fake_executable" \
        "${OSACOMPILE:-osacompile}" -o "$temp_root/sshfling.scpt" \
          "$domain_root/applescript/sshfling.applescript"
      SSHFLING_TEST_EXECUTABLE="$fake_executable" \
        "$tool" "$temp_root/sshfling.scpt" --self-test >/dev/null
      ;;
    vbscript)
      require_tool "$tool" 'VBScript' || return
      "$tool" //E:vbscript //Nologo \
        "$domain_root/vbscript/sshfling.vbs" --self-test
      ;;
    delphi-object-pascal)
      require_tool "$tool" 'Free Pascal/Object Pascal' || return
      install -d -m 0755 "$temp_root/fpc-units" "$temp_root/fpc-bin"
      "$tool" -Mobjfpc -Sh \
        -Fu"$domain_root/object-pascal" \
        -FU"$temp_root/fpc-units" \
        -FE"$temp_root/fpc-bin" \
        "$domain_root/object-pascal/sshfling_cli.pas" >/dev/null
      set +e
      SSHFLING_EXECUTABLE="$fake_executable" \
        "$temp_root/fpc-bin/sshfling_cli" \
          --probe 'argument with spaces' "literal;\$()&"
      status=$?
      set -e
      [[ "$status" -eq 23 ]] || \
        fail "Object Pascal launcher returned $status; expected 23"
      ;;
    *) fail "no candidate gate is defined for: $slug" ;;
  esac
}

gate_one() {
  local slug="$1"
  local row language disposition surface validator
  local temp_root fake_executable

  row="$(manifest_row "$slug")" || {
    printf 'Unknown domain-language slug: %s\n' "$slug" >&2
    return 64
  }
  IFS=$'\t' read -r _ language disposition surface validator <<<"$row"
  if [[ "$disposition" == 'blocked' ]]; then
    printf '%s is blocked by design; no SSHFling launcher/package is emitted.\n' \
      "$language" >&2
    printf 'See docs/language-external-blockers.md (target:%s).\n' "$slug" >&2
    return 78
  fi

  temp_root="$(mktemp -d "${TMPDIR:-/tmp}/sshfling-domain-${slug}.XXXXXX")"
  fake_executable="$(prepare_fake_executable "$temp_root")"
  if gate_candidate "$slug" "$temp_root" "$fake_executable"; then
    rm -rf "$temp_root"
    printf '%s candidate conformance gate passed; support status is unchanged.\n' "$language"
  else
    local result=$?
    rm -rf "$temp_root"
    return "$result"
  fi
}

gate_set() {
  local include_blocked="$1"
  local slug language disposition surface validator
  local failures=0

  while IFS=$'\t' read -r slug language disposition surface validator; do
    if [[ "$include_blocked" != '1' && "$disposition" == 'blocked' ]]; then
      continue
    fi
    if ! gate_one "$slug"; then
      failures=$((failures + 1))
    fi
  done < <(tail -n +2 "$manifest")

  if [[ "$failures" -ne 0 ]]; then
    printf '%d domain-language gate(s) failed closed.\n' "$failures" >&2
    return 1
  fi
}

refuse_package() {
  local slug="$1"
  local row language
  row="$(manifest_row "$slug")" || {
    printf 'Unknown domain-language slug: %s\n' "$slug" >&2
    return 64
  }
  IFS=$'\t' read -r _ language _ _ _ <<<"$row"
  printf '%s remains unsupported; release artifact creation is disabled.\n' "$language" >&2
  printf '%s\n' \
    'A passing candidate gate is validation evidence, not authorization to publish.' >&2
  return 78
}

action="${1:-audit}"
case "$action" in
  audit)
    [[ "$#" -eq 1 || "$#" -eq 0 ]] || { usage >&2; exit 64; }
    audit_manifest
    ;;
  status)
    [[ "$#" -eq 1 ]] || { usage >&2; exit 64; }
    audit_manifest >/dev/null
    status_report
    ;;
  gate)
    [[ "$#" -eq 2 ]] || { usage >&2; exit 64; }
    audit_manifest >/dev/null
    gate_one "$2"
    ;;
  gate-candidates)
    [[ "$#" -eq 1 ]] || { usage >&2; exit 64; }
    audit_manifest >/dev/null
    gate_set 0
    ;;
  gate-all)
    [[ "$#" -eq 1 ]] || { usage >&2; exit 64; }
    audit_manifest >/dev/null
    gate_set 1
    ;;
  package)
    [[ "$#" -eq 2 ]] || { usage >&2; exit 64; }
    audit_manifest >/dev/null
    refuse_package "$2"
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 64
    ;;
esac
