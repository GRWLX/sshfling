#!/usr/bin/env bash
set -euo pipefail

version="${FLING_VERSION:-0.1.0}"
identifier="${FLING_PKG_IDENTIFIER:-io.fling.cli}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dist_dir="$repo_root/dist"
build_root="$repo_root/build/pkg"
payload="$build_root/payload"
component_pkg="$build_root/fling-component.pkg"
product_pkg="$dist_dir/fling-${version}.pkg"

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
install -d "$payload/etc/fling" "$payload/usr/local/bin" "$payload/usr/local/share/fling/templates" "$dist_dir"

install -m 0755 "$repo_root/bin/fling" "$payload/usr/local/bin/fling"
install -m 0644 "$repo_root/packaging/policy.json" "$payload/etc/fling/policy.json"

# shellcheck source=packaging/copy-templates.sh
source "$repo_root/packaging/copy-templates.sh"
copy_fling_templates "$repo_root" "$payload/usr/local/share/fling/templates"

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
