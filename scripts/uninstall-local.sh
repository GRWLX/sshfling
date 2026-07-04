#!/usr/bin/env bash
set -euo pipefail

prefix="${PREFIX:-$HOME/.local}"

rm -f "$prefix/bin/sshfling"
rm -rf "$prefix/share/sshfling"

echo "Removed $prefix/bin/sshfling"
echo "Removed $prefix/share/sshfling"
