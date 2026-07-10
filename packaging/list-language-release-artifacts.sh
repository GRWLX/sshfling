#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=packaging/version.sh
# shellcheck disable=SC1091
source "$repo_root/packaging/version.sh"

version="$(validate_sshfling_version "${1:?release version is required}")"
group="${2:-all}"

declare -A emitted=()

emit_file() {
  local file="$1"
  if [[ -n "${emitted[$file]:-}" ]]; then
    echo "duplicate language release artifact: $file" >&2
    exit 1
  fi
  emitted["$file"]=1
  printf '%s\n' "$file"
}

emit_scripting() {
  local slug
  for slug in tcl awk sed lua zsh fish elvish nushell powershell guix-scheme; do
    emit_file "sshfling-${slug}-${version}.tar.gz"
  done
  emit_file "sshfling-${version}-1.all.rock"
  emit_file "sshfling-scripting-languages-${version}-validation.tsv"
}

emit_tab_registry() {
  local registry="$1"
  local identifier
  local _rest

  while IFS=$'\t' read -r identifier _rest; do
    [[ -z "$identifier" || "$identifier" == "id" ]] && continue
    if [[ ! "$identifier" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
      echo "invalid language identifier in $registry: $identifier" >&2
      exit 1
    fi
    emit_file "sshfling-${identifier}-${version}.tar.gz"
  done <"$registry"
}

emit_functional() {
  emit_tab_registry "$repo_root/packaging/functional-languages/languages.tsv"
  emit_tab_registry "$repo_root/packaging/scientific-languages/languages.tsv"
  emit_tab_registry "$repo_root/packaging/beam-languages/languages.tsv"
  emit_file "sshfling-functional-languages-${version}-validation.tsv"
}

emit_systems() {
  local registry="$repo_root/packaging/systems-languages/packages.tsv"
  local identifier
  local _rest

  while IFS='|' read -r identifier _rest; do
    [[ -z "$identifier" || "$identifier" == \#* ]] && continue
    if [[ ! "$identifier" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
      echo "invalid language identifier in $registry: $identifier" >&2
      exit 1
    fi
    emit_file "sshfling-${identifier}-${version}.tar.gz"
  done <"$registry"
  emit_file "sshfling-systems-languages-${version}-validation.tsv"
}

case "$group" in
  scripting)
    emit_scripting
    ;;
  functional)
    emit_functional
    ;;
  systems)
    emit_systems
    ;;
  catalog)
    emit_functional
    emit_systems
    ;;
  all)
    emit_scripting
    emit_functional
    emit_systems
    ;;
  *)
    echo "unknown language artifact group: $group" >&2
    exit 2
    ;;
esac
