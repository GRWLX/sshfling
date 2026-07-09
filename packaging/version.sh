#!/usr/bin/env bash

validate_sshfling_version() {
  local version="${1:-}"
  if [[ ! "$version" =~ ^[0-9]+[.][0-9]+[.][0-9]+$ ]]; then
    echo "Invalid SSHFling package version." >&2
    echo "Use exactly three numeric components, for example: 0.1.12" >&2
    return 2
  fi
  printf '%s\n' "$version"
}

sshfling_source_version() {
  local repo_root="${1:-$(pwd)}"
  local version
  local version_line

  if [[ ! -r "$repo_root/bin/sshfling" ]]; then
    echo "Could not read bin/sshfling." >&2
    return 2
  fi

  version_line="$(grep -E '^VERSION[[:space:]]*=' "$repo_root/bin/sshfling" | sed -n '1p')"
  if [[ -z "$version_line" ]]; then
    echo "VERSION constant was not found in bin/sshfling." >&2
    return 2
  fi

  version="${version_line#*=}"
  version="${version#"${version%%[![:space:]]*}"}"
  version="${version%%#*}"
  version="${version%"${version##*[![:space:]]}"}"
  if [[ "$version" == \"*\" && "$version" == *\" ]]; then
    version="${version:1:${#version}-2}"
  elif [[ "$version" == \'*\' && "$version" == *\' ]]; then
    version="${version:1:${#version}-2}"
  fi
  validate_sshfling_version "$version"
}

assert_sshfling_version_matches_source() {
  local version
  local source_version
  local repo_root="${2:-$(pwd)}"

  source_version="$(sshfling_source_version "$repo_root")" || return
  if [[ -z "${1:-}" ]]; then
    printf '%s\n' "$source_version"
    return 0
  fi

  version="$(validate_sshfling_version "$1")" || return

  if [[ "$version" != "$source_version" ]]; then
    echo "Package version $version does not match bin/sshfling VERSION $source_version." >&2
    echo "Update bin/sshfling VERSION or use a matching release tag/input." >&2
    return 2
  fi

  printf '%s\n' "$version"
}
