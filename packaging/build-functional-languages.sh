#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if ! python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)'; then
    printf '%s\n' 'build-functional-languages: Python >= 3.11 is required' >&2
    exit 2
fi
exec python3 "$repo_root/packaging/build-functional-languages.py" "$@"
