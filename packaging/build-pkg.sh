#!/usr/bin/env bash
set -euo pipefail

identifier="${SSHFLING_PKG_IDENTIFIER:-io.sshfling.cli}"
sign_identity="${SSHFLING_PKG_SIGN_IDENTITY:-}"
sign_keychain="${SSHFLING_PKG_SIGN_KEYCHAIN:-}"
sign_timestamp="${SSHFLING_PKG_SIGN_TIMESTAMP:-auto}"
require_signing="${SSHFLING_PKG_REQUIRE_SIGNING:-}"
notary_profile="${SSHFLING_PKG_NOTARY_PROFILE:-}"
require_notarization="${SSHFLING_PKG_REQUIRE_NOTARIZATION:-}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=packaging/version.sh
source "$repo_root/packaging/version.sh"
version="$(assert_sshfling_version_matches_source "${SSHFLING_VERSION:-}" "$repo_root")"
dist_dir="$repo_root/dist"
build_root="$repo_root/build/pkg"
payload="$build_root/payload"
resources="$build_root/resources"
scripts="$build_root/scripts"
distribution="$build_root/Distribution.xml"
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

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

if is_truthy "$require_signing" && [[ -z "$sign_identity" ]]; then
  echo "SSHFLING_PKG_REQUIRE_SIGNING requires SSHFLING_PKG_SIGN_IDENTITY." >&2
  exit 2
fi
if [[ -n "$notary_profile" && -z "$sign_identity" ]]; then
  echo "SSHFLING_PKG_NOTARY_PROFILE requires SSHFLING_PKG_SIGN_IDENTITY." >&2
  exit 2
fi
if is_truthy "$require_notarization" && [[ -z "$notary_profile" ]]; then
  echo "SSHFLING_PKG_REQUIRE_NOTARIZATION requires SSHFLING_PKG_NOTARY_PROFILE." >&2
  exit 2
fi
if [[ -n "$notary_profile" ]] && ! command -v xcrun >/dev/null 2>&1; then
  echo "xcrun is required when macOS pkg notarization is enabled." >&2
  exit 127
fi

rm -rf "$build_root"
install -d "$payload/usr/local/bin" "$payload/usr/local/share/sshfling" "$payload/usr/local/share/sshfling/defaults" "$payload/usr/local/share/sshfling/templates" "$resources" "$scripts" "$dist_dir"

install -m 0755 "$repo_root/bin/sshfling" "$payload/usr/local/bin/sshfling"
install -m 0644 "$repo_root/packaging/policy.json" "$payload/usr/local/share/sshfling/defaults/policy.json"
install -m 0644 "$repo_root/LICENSE" "$payload/usr/local/share/sshfling/LICENSE"
install -m 0644 "$repo_root/LICENSE" "$resources/LICENSE"

# shellcheck source=packaging/copy-templates.sh
source "$repo_root/packaging/copy-templates.sh"
copy_sshfling_templates "$repo_root" "$payload/usr/local/share/sshfling/templates"

cat >"$scripts/postinstall" <<'POSTINSTALL'
#!/bin/sh
set -e

policy_dir=/etc/sshfling
policy_file=$policy_dir/policy.json
default_policy=/usr/local/share/sshfling/defaults/policy.json

if [ -L "$policy_dir" ] || { [ -e "$policy_dir" ] && [ ! -d "$policy_dir" ]; }; then
  echo "SSHFling policy path exists but is not a directory: $policy_dir" >&2
  exit 1
fi

install -d -m 0755 -o root -g wheel "$policy_dir" 2>/dev/null || install -d -m 0755 "$policy_dir"
if [ -L "$policy_file" ]; then
  echo "SSHFling policy file is a symlink; preserving operator-managed policy: $policy_file" >&2
elif [ ! -e "$policy_file" ]; then
  install -m 0644 -o root -g wheel "$default_policy" "$policy_file" 2>/dev/null \
    || install -m 0644 "$default_policy" "$policy_file"
elif [ -f "$policy_file" ]; then
  chown root:wheel "$policy_file" 2>/dev/null || true
  chmod 0644 "$policy_file" 2>/dev/null || true
else
  echo "SSHFling policy path exists but is not a regular file: $policy_file" >&2
  exit 1
fi

exit 0
POSTINSTALL
chmod 0755 "$scripts/postinstall"

cat >"$resources/README.pkg.txt" <<README
SSHFling ${version} package notes

Installed files:
- /usr/local/bin/sshfling
- /usr/local/share/sshfling
- /usr/local/share/sshfling/defaults/policy.json

Install-time state:
- The postinstall script creates /etc/sshfling/policy.json from the packaged
  default only when that file is absent.
- Existing /etc/sshfling/policy.json content is not overwritten on install or
  upgrade because it can be operator-managed policy.

Runtime dependencies:
- The macOS pkg does not bundle Python or OpenSSH.
- Client commands require python3 and OpenSSH client tools on PATH.
- Server-side host setup requires the target host's OpenSSH server tooling.

Uninstall and revert scope:
- The published uninstall helper removes the SSHFling command and packaged
  templates, then forgets the pkg receipt.
- It intentionally preserves /etc/sshfling because that directory can contain
  local policy, CA material, or operator-managed configuration.
- Package uninstall does not remove host SSH configuration, temporary password
  grant state, local CA keys, Python, OpenSSH, or other dependency state.
- Exact preinstall state restoration must come from MDM, fleet configuration,
  backups, or another source of recorded original state.
README

cat >"$distribution" <<XML
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="1">
  <title>SSHFling</title>
  <readme file="README.pkg.txt" mime-type="text/plain"/>
  <license file="LICENSE"/>
  <options customize="never" require-scripts="false"/>
  <domains enable_anywhere="false" enable_currentUserHome="false" enable_localSystem="true"/>
  <choices-outline>
    <line choice="default"/>
  </choices-outline>
  <choice id="default" title="SSHFling">
    <pkg-ref id="$identifier"/>
  </choice>
  <pkg-ref id="$identifier" version="$version" onConclusion="none">sshfling-component.pkg</pkg-ref>
</installer-gui-script>
XML

pkgbuild \
  --root "$payload" \
  --scripts "$scripts" \
  --identifier "$identifier" \
  --version "$version" \
  --install-location / \
  "$component_pkg"

productbuild_args=(
  --distribution "$distribution"
  --package-path "$build_root"
  --resources "$resources"
)
if [[ -n "$sign_identity" ]]; then
  productbuild_args+=(--sign "$sign_identity")
  if [[ -n "$sign_keychain" ]]; then
    productbuild_args+=(--keychain "$sign_keychain")
  fi
  case "$sign_timestamp" in
    ""|auto) ;;
    1|true|TRUE|yes|YES) productbuild_args+=(--timestamp) ;;
    none|NONE|0|false|FALSE|no|NO) productbuild_args+=(--timestamp=none) ;;
    *)
      echo "SSHFLING_PKG_SIGN_TIMESTAMP must be auto, none, or a truthy value." >&2
      exit 2
      ;;
  esac
fi

productbuild \
  "${productbuild_args[@]}" \
  "$product_pkg"

if [[ -n "$sign_identity" ]]; then
  pkgutil --check-signature "$product_pkg"
fi

if [[ -n "$notary_profile" ]]; then
  xcrun notarytool submit "$product_pkg" --keychain-profile "$notary_profile" --wait
  xcrun stapler staple "$product_pkg"
  xcrun stapler validate "$product_pkg"
  spctl -a -vv -t install "$product_pkg"
fi

echo "$product_pkg"
