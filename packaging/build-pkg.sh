#!/usr/bin/env bash
set -euo pipefail

version="${SSHFLING_VERSION:-0.1.1}"
identifier="${SSHFLING_PKG_IDENTIFIER:-io.sshfling.cli}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dist_dir="$repo_root/dist"
build_root="$repo_root/build/pkg"
payload="$build_root/payload"
component_pkg="$build_root/sshfling-component.pkg"
product_pkg="$dist_dir/sshfling-${version}.pkg"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "macOS package builds must run on macOS." >&2
  exit 127
fi

for tool in pkgbuild productbuild; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "$tool is required to build a macOS pkg." >&2
    exit 127
  fi
done

rm -rf "$build_root"
install -d "$payload/etc/sshfling" "$payload/usr/local/bin" "$payload/usr/local/share/sshfling" "$payload/usr/local/share/sshfling/templates" "$dist_dir"

install -m 0755 "$repo_root/bin/sshfling" "$payload/usr/local/bin/sshfling"
install -m 0644 "$repo_root/packaging/policy.json" "$payload/etc/sshfling/policy.json"
install -m 0644 "$repo_root/LICENSE" "$payload/usr/local/share/sshfling/LICENSE"

# shellcheck source=packaging/copy-templates.sh
source "$repo_root/packaging/copy-templates.sh"
copy_sshfling_templates "$repo_root" "$payload/usr/local/share/sshfling/templates"

pkgbuild \
  --root "$payload" \
  --identifier "$identifier" \
  --version "$version" \
  --install-location / \
  "$component_pkg"

productbuild \
  --package "$component_pkg" \
  "$product_pkg"

echo "$product_pkg"
