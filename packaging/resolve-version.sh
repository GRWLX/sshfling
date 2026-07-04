#!/usr/bin/env bash
set -euo pipefail

input_version="${1:-}"

if [[ -n "$input_version" ]]; then
  echo "$input_version"
elif [[ "${GITHUB_REF_TYPE:-}" == "tag" ]]; then
  echo "${GITHUB_REF_NAME#v}"
else
  python3 -c 'import ast, pathlib; print(next(ast.literal_eval(line.split("=", 1)[1].strip()) for line in pathlib.Path("bin/sshfling").read_text(encoding="utf-8").splitlines() if line.startswith("VERSION = ")))'
fi
