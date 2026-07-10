#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"

# shellcheck source=packaging/version.sh
source "$repo_root/packaging/version.sh"
version="$(assert_sshfling_version_matches_source "${VERSION:-}" "$repo_root")"
repository="${REPOSITORY:-GRWLX/sshfling}"
owner="${OWNER:-${repository%%/*}}"
source_commit="${GITHUB_SHA:-release-rehearsal}"
source_date_epoch="${SOURCE_DATE_EPOCH:-1700000000}"
scripting_files=(
  "sshfling-tcl-${version}.tar.gz"
  "sshfling-awk-${version}.tar.gz"
  "sshfling-sed-${version}.tar.gz"
  "sshfling-lua-${version}.tar.gz"
  "sshfling-zsh-${version}.tar.gz"
  "sshfling-fish-${version}.tar.gz"
  "sshfling-elvish-${version}.tar.gz"
  "sshfling-nushell-${version}.tar.gz"
  "sshfling-powershell-${version}.tar.gz"
  "sshfling-guix-scheme-${version}.tar.gz"
  "sshfling-${version}-1.all.rock"
  "sshfling-scripting-languages-${version}-validation.tsv"
)
mapfile -t catalog_files < <(
  bash "$repo_root/packaging/list-language-release-artifacts.sh" "$version" catalog
)

export LC_ALL=C
export TZ=UTC
export SOURCE_DATE_EPOCH="$source_date_epoch"
umask 022

mkdir -p "$repo_root/build"
tmpdir="$(mktemp -d "$repo_root/build/release-package-rehearsal.XXXXXX")"
signing_home=""

cleanup() {
  local status=$?

  if [[ -n "$signing_home" && -d "$signing_home" ]] && command -v gpgconf >/dev/null 2>&1; then
    GNUPGHOME="$signing_home" gpgconf --kill all >/dev/null 2>&1 || true
  fi
  if (( status != 0 )) && [[ -d "$tmpdir" ]]; then
    echo "package publishing release rehearsal failed; captured logs:" >&2
    while IFS= read -r log_file; do
      echo "==> ${log_file#"$tmpdir"/}" >&2
      tail -n 40 "$log_file" >&2 || true
    done < <(find "$tmpdir" -maxdepth 1 -type f -name '*.log' -print | sort)
  fi
  if [[ "${KEEP_RELEASE_REHEARSAL_TMP:-}" == "1" || "${KEEP_RELEASE_REHEARSAL_TMP:-}" == "true" ]]; then
    echo "kept release rehearsal workspace: $tmpdir" >&2
  else
    rm -rf "$tmpdir"
  fi
  return "$status"
}
trap cleanup EXIT

export HOME="$tmpdir/home"
export XDG_CACHE_HOME="$tmpdir/xdg-cache"
export XDG_CONFIG_HOME="$tmpdir/xdg-config"
install -d "$HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME"

package_dist="$tmpdir/package-dist"
mkdir -p "$package_dist"

fail() {
  echo "$*" >&2
  exit 1
}

require_tools() {
  local missing=()
  local tool

  for tool in "$@"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      missing+=("$tool")
    fi
  done

  if ((${#missing[@]} != 0)); then
    echo "missing required release rehearsal tools: ${missing[*]}" >&2
    echo "Install dpkg-dev, createrepo-c, gnupg, rpm, and rpm-build before running this rehearsal." >&2
    exit 127
  fi
}

write_tiny_cli() {
  local path="$1"
  install -d "$(dirname "$path")"
  cat >"$path" <<SH
#!/usr/bin/env sh
echo "sshfling ${version}"
SH
  chmod 0755 "$path"
}

normalize_tree_timestamps() {
  local path="$1"

  find "$path" -exec touch -h -d "@$source_date_epoch" {} +
}

create_deterministic_tarball() {
  local source_parent="$1"
  local output="$2"
  local entry="$3"

  tar \
    --sort=name \
    --mtime="@$source_date_epoch" \
    --owner=0 \
    --group=0 \
    --numeric-owner \
    --use-compress-program="gzip -n" \
    -C "$source_parent" \
    -cf "$output" \
    "$entry"
}

build_source_tarball() {
  local source_parent="$tmpdir/source"
  local source_dir="$source_parent/sshfling-$version"

  install -d "$source_dir/bin" "$source_dir/production" "$source_dir/packaging"
  write_tiny_cli "$source_dir/bin/sshfling"
  write_tiny_cli "$source_dir/production/sshfling-login-shell"
  write_tiny_cli "$source_dir/production/sshfling-session"
  printf 'SSHFling release rehearsal artifact\n' >"$source_dir/README.md"
  printf 'SSHFling commercial license placeholder for release rehearsal\n' >"$source_dir/LICENSE"
  printf '{}\n' >"$source_dir/packaging/policy.json"
  normalize_tree_timestamps "$source_dir"
  create_deterministic_tarball "$source_parent" "$package_dist/sshfling-$version.tar.gz" "sshfling-$version"
}

build_deb() {
  local stage="$tmpdir/deb/sshfling_${version}_all"

  install -d "$stage/DEBIAN" "$stage/usr/bin"
  write_tiny_cli "$stage/usr/bin/sshfling"
  cat >"$stage/DEBIAN/control" <<CONTROL
Package: sshfling
Version: $version
Section: utils
Priority: optional
Architecture: all
Maintainer: SSHFling Maintainers <root@localhost>
Description: SSHFling release rehearsal package
 Minimal package used only to exercise public package repository metadata.
CONTROL
  normalize_tree_timestamps "$stage"
  dpkg-deb --root-owner-group --build "$stage" "$package_dist/sshfling_${version}_all.deb" \
    >"$tmpdir/dpkg-deb.log" 2>&1
}

build_rpm() {
  local topdir="$tmpdir/rpmbuild"
  local source_parent="$tmpdir/rpm-source"
  local source_dir="$source_parent/sshfling-$version"
  local spec="$topdir/SPECS/sshfling.spec"
  local built_rpm="$topdir/RPMS/noarch/sshfling-$version-1.noarch.rpm"

  install -d "$topdir/BUILD" "$topdir/RPMS" "$topdir/SOURCES" "$topdir/SPECS" "$topdir/SRPMS"
  install -d "$source_dir/bin"
  write_tiny_cli "$source_dir/bin/sshfling"
  normalize_tree_timestamps "$source_dir"
  create_deterministic_tarball "$source_parent" "$topdir/SOURCES/sshfling-$version.tar.gz" "sshfling-$version"

  cat >"$spec" <<SPEC
Name: sshfling
Version: $version
Release: 1
Summary: SSHFling release rehearsal package
License: LicenseRef-SSHFling-Commercial
BuildArch: noarch
Source0: sshfling-$version.tar.gz

%description
Minimal package used only to exercise public package repository metadata.

%prep
%setup -q

%build

%install
mkdir -p %{buildroot}/usr/bin
install -m 0755 bin/sshfling %{buildroot}/usr/bin/sshfling

%files
/usr/bin/sshfling
SPEC

  rpmbuild \
    --define "_topdir $topdir" \
    --define "_build_id_links none" \
    --define "_buildhost sshfling-rehearsal.local" \
    --define "use_source_date_epoch_as_buildtime 1" \
    --define "clamp_mtime_to_source_date_epoch 1" \
    -bb "$spec" >"$tmpdir/rpmbuild.log" 2>&1
  test -s "$built_rpm"
  cp "$built_rpm" "$package_dist/"
}

build_direct_downloads() {
  printf 'NuGet global tool placeholder for release rehearsal\n' >"$package_dist/SSHFling.Tool.$version.nupkg"
  printf 'NuGet library placeholder for release rehearsal\n' >"$package_dist/SSHFling.$version.nupkg"
  printf 'Java executable JAR placeholder for release rehearsal\n' >"$package_dist/sshfling-cli-$version.jar"
  printf 'Java Javadocs JAR placeholder for release rehearsal\n' >"$package_dist/sshfling-cli-$version-javadoc.jar"
  printf 'Java sources JAR placeholder for release rehearsal\n' >"$package_dist/sshfling-cli-$version-sources.jar"
  printf 'Java Maven POM placeholder for release rehearsal\n' >"$package_dist/sshfling-cli-$version.pom"
  printf 'Node.js npm package placeholder for release rehearsal\n' >"$package_dist/sshfling-$version.tgz"
  printf 'Python wheel placeholder for release rehearsal\n' >"$package_dist/sshfling-$version-py3-none-any.whl"
  printf 'Go module placeholder for release rehearsal\n' >"$package_dist/sshfling-go-$version.zip"
  printf 'Rust crate placeholder for release rehearsal\n' >"$package_dist/sshfling-cli-$version.crate"
  printf 'PHP Composer package placeholder for release rehearsal\n' >"$package_dist/sshfling-php-$version.zip"
  printf 'Ruby gem placeholder for release rehearsal\n' >"$package_dist/sshfling-$version.gem"
  printf 'C and C++ native libraries placeholder for release rehearsal\n' >"$package_dist/sshfling-native-$version.tar.gz"
  printf 'Perl source distribution placeholder for release rehearsal\n' >"$package_dist/sshfling-perl-$version.tar.gz"
  for language in tcl awk sed lua zsh fish elvish nushell powershell guix-scheme; do
    printf '%s source archive placeholder for release rehearsal\n' "$language" \
      >"$package_dist/sshfling-$language-$version.tar.gz"
  done
  printf 'LuaRocks package placeholder for release rehearsal\n' \
    >"$package_dist/sshfling-$version-1.all.rock"
  {
    printf 'RESULT\tbatch\tsource-version\tPASS\t%s\n' "$version"
    printf 'RESULT\tnushell\tsource-runtime\tSKIP\trehearsal-runtime-not-installed\n'
    printf 'RESULT\tpowershell\tsource-runtime\tSKIP\trehearsal-runtime-not-installed\n'
    printf 'RESULT\tguix-scheme\tguix-definition\tSKIP\trehearsal-runtime-not-installed\n'
  } >"$package_dist/sshfling-scripting-languages-$version-validation.tsv"
  for catalog_file in "${catalog_files[@]}"; do
    printf 'language catalog artifact placeholder for release rehearsal: %s\n' "$catalog_file" \
      >"$package_dist/$catalog_file"
  done
  printf 'macOS pkg placeholder for release rehearsal\n' >"$package_dist/sshfling-$version.pkg"
  printf 'Windows MSI placeholder for release rehearsal\n' >"$package_dist/sshfling-$version.msi"
  printf 'Windows zip placeholder for release rehearsal\n' >"$package_dist/sshfling-$version-windows.zip"
}

build_local_artifacts() {
  build_source_tarball
  build_deb
  build_rpm
  build_direct_downloads
  normalize_tree_timestamps "$package_dist"
}

create_signing_material() {
  local private_key_file="$tmpdir/repo-signing-private.asc"

  signing_home="$tmpdir/signing-keyring"
  install -d -m 0700 "$signing_home"
  GNUPGHOME="$signing_home" gpg --batch --pinentry-mode loopback --passphrase '' \
    --quick-generate-key "SSHFling release rehearsal <packages@sshfling.local>" rsa3072 sign 1d \
    >"$tmpdir/gpg-generate.log" 2>&1
  signing_fingerprint="$(
    GNUPGHOME="$signing_home" gpg --batch --list-secret-keys --with-colons 2>"$tmpdir/gpg-list.log" |
      awk -F: '/^fpr:/ {print toupper($10); exit}'
  )"
  test -n "$signing_fingerprint"
  GNUPGHOME="$signing_home" gpg --batch --yes --armor --export-secret-keys "$signing_fingerprint" \
    >"$private_key_file"
  signing_private_key="$(cat "$private_key_file")"
}

run_build_public_web() {
  local label="$1"
  local public_dir="$2"
  shift 2

  env \
    VERSION="$version" \
    REPOSITORY="$repository" \
    OWNER="$owner" \
    SOURCE_DATE_EPOCH="$source_date_epoch" \
    "$@" \
    bash "$repo_root/packaging/build-public-web.sh" "$package_dist" "$public_dir" \
    >"$tmpdir/$label-build.log" 2>&1
}

run_verify_public_web() {
  local label="$1"
  local public_dir="$2"
  shift 2

  env \
    VERSION="$version" \
    REPOSITORY="$repository" \
    OWNER="$owner" \
    "$@" \
    bash "$repo_root/packaging/verify-public-web.sh" "$public_dir" \
    >"$tmpdir/$label-verify.log" 2>&1
}

write_package_site_evidence() {
  local public_dir="$1"
  local name
  local bytes
  local hash

  {
    echo "# SSHFling package site evidence"
    echo
    echo "Version: $version"
    echo "Repository: $repository"
    echo "Commit: $source_commit"
    echo "PowerShell, Nushell, and Guix Scheme source archives are runtime-gated; their publication does not assert runtime PASS. Per-check status is recorded in sshfling-scripting-languages-$version-validation.tsv."
    if [[ -f "$public_dir/sshfling-repo-fingerprint.txt" ]]; then
      echo "Repository signing fingerprint: \`$(tr -d '[:space:]' <"$public_dir/sshfling-repo-fingerprint.txt")\`"
    fi
    echo
    echo "| Download | Bytes | SHA-256 |"
    echo "| --- | ---: | --- |"
    while IFS= read -r -d '' file; do
      name="${file#"$public_dir/downloads/"}"
      bytes="$(wc -c <"$file" | tr -d '[:space:]')"
      hash="$(sha256sum "$file" | awk '{print $1}')"
      printf "| \`%s\` | %s | \`%s\` |\n" "$name" "$bytes" "$hash"
    done < <(find "$public_dir/downloads" -maxdepth 1 -type f ! -name SHA256SUMS -print0 | sort -z)
  } >"$public_dir/RELEASE-EVIDENCE.md"
}

generate_and_validate_evidence() {
  local label="$1"
  local public_dir="$2"
  local require_signatures="$3"
  local output_dir="$tmpdir/evidence-$label"
  local args=(
    "$repo_root/tools/generate_release_evidence.py"
    --repo-root "$repo_root"
    --mode package-site
    --public-dir "$public_dir"
    --version "$version"
    --owner "$owner"
    --source-commit "$source_commit"
    --output-dir "$output_dir"
  )

  if [[ "$require_signatures" == "1" ]]; then
    args+=(--require-repo-signatures)
  fi

  python3 "${args[@]}" >"$tmpdir/$label-evidence-generate.log"
  python3 "$repo_root/tools/release_matrix_validate.py" \
    --repo-root "$repo_root" \
    --matrix "$output_dir/package-site-matrix.csv" \
    --manifest "$output_dir/package-site-manifest.json" \
    --max-errors 5 >"$tmpdir/$label-evidence-validate.log"
}

require_tools \
  awk \
  createrepo_c \
  diff \
  dpkg-deb \
  dpkg-scanpackages \
  gpg \
  gzip \
  openssl \
  python3 \
  rpm \
  rpmbuild \
  rpmsign \
  sha256sum \
  tar

build_local_artifacts
create_signing_material

unexpected_package="$package_dist/sshfling-unexpected-$version.tar.gz"
printf 'unexpected package artifact\n' >"$unexpected_package"
if run_build_public_web unexpected-package "$tmpdir/public-unexpected-package"; then
  fail "expected public package build to reject an unexpected package artifact"
fi
grep -Fq "Package artifact set must exactly match" "$tmpdir/unexpected-package-build.log"
rm -f "$unexpected_package"

missing_package="$package_dist/sshfling-nushell-$version.tar.gz"
mv "$missing_package" "$tmpdir/"
if run_build_public_web missing-package "$tmpdir/public-missing-package"; then
  fail "expected public package build to reject a missing scripting-language artifact"
fi
grep -Fq "Package artifact set must exactly match" "$tmpdir/missing-package-build.log"
mv "$tmpdir/$(basename "$missing_package")" "$missing_package"

missing_catalog_package="$package_dist/sshfling-haskell-$version.tar.gz"
mv "$missing_catalog_package" "$tmpdir/"
if run_build_public_web missing-catalog-package "$tmpdir/public-missing-catalog-package"; then
  fail "expected public package build to reject a missing language-catalog artifact"
fi
grep -Fq "Package artifact set must exactly match" "$tmpdir/missing-catalog-package-build.log"
mv "$tmpdir/$(basename "$missing_catalog_package")" "$missing_catalog_package"

unsigned_public="$tmpdir/public-unsigned"
run_build_public_web unsigned "$unsigned_public"
unsigned_repeat_public="$tmpdir/public-unsigned-repeat"
run_build_public_web unsigned-repeat "$unsigned_repeat_public"
if ! diff -qr "$unsigned_public" "$unsigned_repeat_public" >"$tmpdir/unsigned-repeat-diff.log"; then
  fail "expected unsigned package site builds to be byte-for-byte deterministic"
fi
run_verify_public_web unsigned "$unsigned_public"
for file in "${scripting_files[@]}"; do
  test -s "$unsigned_public/downloads/$file"
  grep -Fq "  $file" "$unsigned_public/downloads/SHA256SUMS"
  grep -Fq "$file" "$unsigned_public/downloads/index.html"
  grep -Fq "$file" "$unsigned_public/index.html"
done
(cd "$unsigned_public/downloads" && sha256sum -c SHA256SUMS >/dev/null)
grep -Fq "Runtime-gated: Nushell" "$unsigned_public/index.html"
grep -Fq "Runtime-gated: PowerShell" "$unsigned_public/index.html"
grep -Fq "Runtime-gated: Guix Scheme" "$unsigned_public/index.html"
grep -Fq '(secure-wrap-program' "$unsigned_public/guix/sshfling.scm"
grep -Fq 'unset BASH_ENV ENV CDPATH GLOBIGNORE' "$unsigned_public/guix/sshfling.scm"
if grep -Fq '(wrap-program' "$unsigned_public/guix/sshfling.scm"; then
  fail "Guix privileged entry points must not use non-privileged Bash wrappers"
fi
if command -v guile >/dev/null 2>&1; then
  guile -c '
    (call-with-input-file (cadr (command-line))
      (lambda (port)
        (let loop ((form (read port)))
          (unless (eof-object? form)
            (loop (read port))))))' \
    "$unsigned_public/guix/sshfling.scm"
fi
guix_wrapper_probe="$tmpdir/guix-secure-wrapper-probe"
guix_bash_env="$tmpdir/guix-malicious-bash-env"
guix_bash_env_marker="$tmpdir/guix-bash-env-ran"
printf ': >%q\n' "$guix_bash_env_marker" >"$guix_bash_env"
{
  printf '#!%s -p\n' "$(command -v bash)"
  printf 'set -eu\n'
  printf 'unset BASH_ENV ENV CDPATH GLOBIGNORE 2>/dev/null || :\n'
  printf 'exit 0\n'
} >"$guix_wrapper_probe"
chmod 0755 "$guix_wrapper_probe"
BASH_ENV="$guix_bash_env" "$guix_wrapper_probe"
test ! -e "$guix_bash_env_marker" \
  || fail "Guix privileged wrapper evaluated BASH_ENV before startup hardening"
test ! -e "$unsigned_public/sshfling-repo.gpg"
test ! -e "$unsigned_public/sshfling-repo.asc"
test ! -e "$unsigned_public/apt/InRelease"
test ! -e "$unsigned_public/rpm/repodata/repomd.xml.asc"
grep -Fq 'expected_repo_fingerprint=""' "$unsigned_public/install.sh"
write_package_site_evidence "$unsigned_public"
generate_and_validate_evidence unsigned "$unsigned_public" 0

unexpected_download_public="$tmpdir/public-unexpected-download"
cp -a "$unsigned_public" "$unexpected_download_public"
printf 'unexpected direct download\n' >"$unexpected_download_public/downloads/unexpected-$version.tar.gz"
if run_verify_public_web unexpected-download "$unexpected_download_public"; then
  fail "expected public package verification to reject an unexpected direct download"
fi
grep -Fq "unexpected file set in downloads" "$tmpdir/unexpected-download-verify.log"

if run_verify_public_web unsigned-require-signatures "$unsigned_public" \
  REQUIRE_REPO_SIGNATURES=1 \
  SSHFLING_REPO_GPG_FINGERPRINT="$signing_fingerprint"; then
  fail "expected public package verification to reject unsigned repository metadata when signatures are required"
fi
grep -Fq "missing: sshfling-repo.gpg" "$tmpdir/unsigned-require-signatures-verify.log"
grep -Fq "missing: apt/InRelease" "$tmpdir/unsigned-require-signatures-verify.log"
grep -Fq "missing: rpm/repodata/repomd.xml.asc" "$tmpdir/unsigned-require-signatures-verify.log"

signed_public="$tmpdir/public-signed"
run_build_public_web signed "$signed_public" \
  REQUIRE_REPO_SIGNATURES=1 \
  SSHFLING_REPO_GPG_PRIVATE_KEY="$signing_private_key" \
  SSHFLING_REPO_GPG_FINGERPRINT="$signing_fingerprint"
run_verify_public_web signed "$signed_public" \
  REQUIRE_REPO_SIGNATURES=1 \
  SSHFLING_REPO_GPG_FINGERPRINT="$signing_fingerprint"
test -s "$signed_public/sshfling-repo.gpg"
test -s "$signed_public/sshfling-repo.asc"
test -s "$signed_public/apt/InRelease"
test -s "$signed_public/apt/Release.gpg"
test -s "$signed_public/rpm/repodata/repomd.xml.asc"
grep -Fq "$signing_fingerprint" "$signed_public/sshfling-repo-fingerprint.txt"
grep -Fq "expected_repo_fingerprint=\"$signing_fingerprint\"" "$signed_public/install.sh"
write_package_site_evidence "$signed_public"
generate_and_validate_evidence signed "$signed_public" 1

if run_verify_public_web signed-wrong-fingerprint "$signed_public" \
  REQUIRE_REPO_SIGNATURES=1 \
  SSHFLING_REPO_GPG_FINGERPRINT="0000000000000000000000000000000000000000"; then
  fail "expected public package verification to reject a mismatched repository signing fingerprint"
fi
grep -Fq "repository signing fingerprint mismatch" "$tmpdir/signed-wrong-fingerprint-verify.log"

missing_key_public="$tmpdir/public-missing-key"
if run_build_public_web missing-key "$missing_key_public" REQUIRE_REPO_SIGNATURES=1; then
  fail "expected public package build to reject required signatures without signing material"
fi
grep -Fq "REQUIRE_REPO_SIGNATURES requires SSHFLING_REPO_GPG_PRIVATE_KEY" "$tmpdir/missing-key-build.log"

missing_fingerprint_public="$tmpdir/public-missing-fingerprint"
if run_build_public_web missing-fingerprint "$missing_fingerprint_public" \
  REQUIRE_REPO_SIGNATURES=1 \
  SSHFLING_REPO_GPG_PRIVATE_KEY="$signing_private_key"; then
  fail "expected public package build to reject required signatures without an approved fingerprint"
fi
grep -Fq "REQUIRE_REPO_SIGNATURES requires SSHFLING_REPO_GPG_FINGERPRINT" "$tmpdir/missing-fingerprint-build.log"

if run_verify_public_web signed-missing-fingerprint "$signed_public" REQUIRE_REPO_SIGNATURES=1; then
  fail "expected public package verification to reject required signatures without an approved fingerprint"
fi
grep -Fq "REQUIRE_REPO_SIGNATURES requires SSHFLING_REPO_GPG_FINGERPRINT" \
  "$tmpdir/signed-missing-fingerprint-verify.log"

echo "package publishing release rehearsal passed"
