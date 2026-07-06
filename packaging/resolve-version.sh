#!/usr/bin/env bash
set -euo pipefail

input_version="${1:-}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=packaging/version.sh
source "$repo_root/packaging/version.sh"

if [[ -n "$input_version" ]]; then
  if [[ "$input_version" =~ ^v[0-9]+[.][0-9]+[.][0-9]+$ ]]; then
    input_version="${input_version#v}"
  fi
  assert_sshfling_version_matches_source "$input_version" "$repo_root"
elif [[ "${GITHUB_REF_TYPE:-}" == "tag" ]]; then
  if [[ ! "${GITHUB_REF_NAME:-}" =~ ^v[0-9]+[.][0-9]+[.][0-9]+$ ]]; then
    echo "Release tags must use vX.Y.Z format, for example v0.1.12." >&2
    exit 2
  fi
  assert_sshfling_version_matches_source "${GITHUB_REF_NAME#v}" "$repo_root"
else
  sshfling_source_version "$repo_root"
fi
