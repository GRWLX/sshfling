#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=packaging/version.sh
source "$repo_root/packaging/version.sh"
version="$(assert_sshfling_version_matches_source "${SSHFLING_VERSION:-}" "$repo_root")"

perl_cmd="${PERL:-perl}"
make_cmd="${MAKE:-make}"
if ! command -v "$perl_cmd" >/dev/null 2>&1; then
  echo "Perl 5.26 or newer is required to build the SSHFling Perl distribution." >&2
  exit 127
fi
if ! "$perl_cmd" -e 'exit($] >= 5.026 ? 0 : 1)'; then
  echo "Perl 5.26 or newer is required to build the SSHFling Perl distribution." >&2
  exit 2
fi
if ! command -v "$make_cmd" >/dev/null 2>&1; then
  echo "make is required to build the SSHFling Perl distribution." >&2
  exit 127
fi
if ! "$perl_cmd" -MExtUtils::MakeMaker -e 1 >/dev/null 2>&1; then
  echo "ExtUtils::MakeMaker is required to build the SSHFling Perl distribution." >&2
  exit 127
fi

dist_dir="$repo_root/dist"
build_root="$repo_root/build/perl"
project_dir="$build_root/project"
install_prefix="$build_root/install"
smoke_project="$build_root/smoke-project"
archive_path="$dist_dir/sshfling-perl-$version.tar.gz"

export LC_ALL=C
export TZ=UTC
export PERL_MM_USE_DEFAULT=1
umask 022

copy_project() {
  rm -rf "$project_dir"
  install -d "$project_dir"
  cp -R "$repo_root/packaging/perl/." "$project_dir/"
  install -m 0644 "$repo_root/LICENSE" "$project_dir/LICENSE"
  install -m 0644 "$repo_root/README.md" "$project_dir/README.md"
  install -d "$project_dir/lib/SSHFling/runtime"
  install -m 0755 "$repo_root/bin/sshfling" "$project_dir/lib/SSHFling/runtime/sshfling.py"

  # shellcheck source=packaging/copy-templates.sh
  source "$repo_root/packaging/copy-templates.sh"
  copy_sshfling_templates "$repo_root" "$project_dir/lib/SSHFling/runtime/templates"

  sed -i "s/our \$VERSION = '0.0.0';/our \$VERSION = '$version';/" "$project_dir/lib/SSHFling.pm"
  grep -Fqx "our \$VERSION = '$version';" "$project_dir/lib/SSHFling.pm"
}

build_distribution() {
  (
    cd "$project_dir"
    "$perl_cmd" Makefile.PL INSTALL_BASE="$install_prefix" >/dev/null
    "$make_cmd" manifest >/dev/null
    "$make_cmd" test
    "$make_cmd" dist >/dev/null
  )

  local built_archive="$project_dir/SSHFling-$version.tar.gz"
  test -s "$built_archive"
  cp "$built_archive" "$archive_path"
  tar -tzf "$archive_path" | grep -Fx "SSHFling-$version/Makefile.PL" >/dev/null
  tar -tzf "$archive_path" | grep -Fx "SSHFling-$version/META.json" >/dev/null
  tar -tzf "$archive_path" | grep -Fx "SSHFling-$version/bin/sshfling" >/dev/null
  tar -tzf "$archive_path" | grep -Fx "SSHFling-$version/lib/SSHFling.pm" >/dev/null
  tar -tzf "$archive_path" | grep -Fx "SSHFling-$version/lib/SSHFling/runtime/sshfling.py" >/dev/null
  tar -tzf "$archive_path" | grep -Fx "SSHFling-$version/lib/SSHFling/runtime/templates/native/sshfling-linux-account" >/dev/null
  tar -tzf "$archive_path" | grep -Fx "SSHFling-$version/lib/SSHFling/runtime/templates/production/sshfling-login-shell" >/dev/null
}

validate_install() {
  (
    cd "$project_dir"
    "$make_cmd" pure_install >/dev/null
  )

  local perl_lib="$install_prefix/lib/perl5"
  local installed_cli="$install_prefix/bin/sshfling"
  test -x "$installed_cli"
  PERL5LIB="$perl_lib" "$perl_cmd" -MSSHFling -e \
    'exit SSHFling::version() eq $ARGV[0] && SSHFling::run("--version") == 0 ? 0 : 1' \
    "$version"
  PERL5LIB="$perl_lib" "$installed_cli" --version | grep -Fx "sshfling $version" >/dev/null
  PERL5LIB="$perl_lib" "$installed_cli" init "$smoke_project" --force --session-seconds 60 >/dev/null
  test -x "$smoke_project/native/sshfling-linux-account"
  test -x "$smoke_project/native/sshfling-unix-identity"
  test -x "$smoke_project/production/sshfling-login-shell"

  rm -rf "$install_prefix"
  test ! -e "$installed_cli"
  if PERL5LIB="$perl_lib" "$perl_cmd" -MSSHFling -e 1 >/dev/null 2>&1; then
    echo "Perl package remained importable after isolated prefix removal." >&2
    exit 1
  fi
}

rm -rf "$build_root"
install -d "$build_root" "$dist_dir"
rm -f "$archive_path"

copy_project
build_distribution
validate_install

printf '%s\n' "$archive_path"
