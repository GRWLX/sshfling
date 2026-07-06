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
  local python_bin=""
  local version

  if command -v python3 >/dev/null 2>&1; then
    python_bin="python3"
  elif command -v python >/dev/null 2>&1; then
    python_bin="python"
  else
    echo "python3 or python is required to read bin/sshfling VERSION." >&2
    return 127
  fi

  version="$("$python_bin" - "$repo_root/bin/sshfling" <<'PY'
import ast
import pathlib
import sys

source = pathlib.Path(sys.argv[1])
for line in source.read_text(encoding="utf-8").splitlines():
    if line.startswith("VERSION = "):
        print(ast.literal_eval(line.split("=", 1)[1].strip()))
        break
else:
    raise SystemExit("VERSION constant was not found in bin/sshfling")
PY
)"
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
