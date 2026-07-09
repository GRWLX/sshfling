#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=packaging/version.sh
source "$repo_root/packaging/version.sh"
version="$(assert_sshfling_version_matches_source "${SSHFLING_VERSION:-}" "$repo_root")"

ruby_cmd="${RUBY:-ruby}"
gem_cmd="${GEM:-gem}"
bundle_cmd="${BUNDLER:-bundle}"
if ! command -v "$ruby_cmd" >/dev/null 2>&1; then
  echo "Ruby 3.0 or newer is required to build the SSHFling gem." >&2
  exit 127
fi
if ! "$ruby_cmd" -e 'exit RUBY_VERSION.split(".").first.to_i >= 3 ? 0 : 1'; then
  echo "Ruby 3.0 or newer is required to build the SSHFling gem." >&2
  exit 2
fi
if ! command -v "$gem_cmd" >/dev/null 2>&1; then
  echo "RubyGems is required to build the SSHFling gem." >&2
  exit 127
fi
if ! command -v "$bundle_cmd" >/dev/null 2>&1; then
  if command -v bundle3.2 >/dev/null 2>&1; then
    bundle_cmd="bundle3.2"
  else
    echo "Bundler is required to validate the SSHFling gem." >&2
    exit 127
  fi
fi

dist_dir="$repo_root/dist"
build_root="$repo_root/build/ruby"
package_dir="$build_root/package"
validation_dir="$build_root/validation"
gem_path="$dist_dir/sshfling-$version.gem"

export LC_ALL=C
export TZ=UTC
umask 022

copy_ruby_project() {
  rm -rf "$package_dir"
  install -d "$package_dir/lib/sshfling" "$package_dir/bin" "$package_dir/runtime"
  install -m 0644 "$repo_root/packaging/ruby/sshfling.gemspec" "$package_dir/sshfling.gemspec"
  install -m 0644 "$repo_root/packaging/ruby/lib/sshfling.rb" "$package_dir/lib/sshfling.rb"
  install -m 0644 "$repo_root/packaging/ruby/lib/sshfling/version.rb" "$package_dir/lib/sshfling/version.rb"
  install -m 0755 "$repo_root/packaging/ruby/bin/sshfling" "$package_dir/bin/sshfling"
  install -m 0644 "$repo_root/LICENSE" "$package_dir/LICENSE"
  install -m 0644 "$repo_root/README.md" "$package_dir/README.md"
  install -m 0755 "$repo_root/bin/sshfling" "$package_dir/runtime/sshfling.py"

  # shellcheck source=packaging/copy-templates.sh
  source "$repo_root/packaging/copy-templates.sh"
  copy_sshfling_templates "$repo_root" "$package_dir/runtime/templates"

  sed -i "s/VERSION = \"0.0.0\"/VERSION = \"$version\"/" "$package_dir/lib/sshfling/version.rb"
  grep -Fqx "  VERSION = \"$version\"" "$package_dir/lib/sshfling/version.rb"
}

validate_ruby_project() {
  "$ruby_cmd" -c "$package_dir/lib/sshfling.rb" >/dev/null
  "$ruby_cmd" -c "$package_dir/lib/sshfling/version.rb" >/dev/null
  "$ruby_cmd" -c "$package_dir/bin/sshfling" >/dev/null
  (
    cd "$package_dir"
    "$gem_cmd" build --strict sshfling.gemspec >/dev/null
  )
}

copy_and_validate_gem() {
  local built_gem="$package_dir/sshfling-$version.gem"

  if [[ ! -s "$built_gem" ]]; then
    echo "Ruby gem was not created: $built_gem" >&2
    exit 1
  fi
  cp "$built_gem" "$gem_path"
  "$gem_cmd" specification "$gem_path" name version required_ruby_version >/dev/null

  "$gem_cmd" contents --show-install-dir --local --version "$version" sshfling >/dev/null 2>&1 || true
  tar -tf "$gem_path" | grep -Fx data.tar.gz >/dev/null
  tar -xOf "$gem_path" data.tar.gz | tar -tzf - | grep -Fx runtime/sshfling.py >/dev/null
  tar -xOf "$gem_path" data.tar.gz | tar -tzf - | grep -Fx runtime/templates/systemd/sshfling-prune.timer >/dev/null
  tar -xOf "$gem_path" data.tar.gz | tar -tzf - | grep -Fx runtime/templates/native/sshfling-linux-account >/dev/null
  tar -xOf "$gem_path" data.tar.gz | tar -tzf - | grep -Fx runtime/templates/native/sshfling-unix-identity >/dev/null
  tar -xOf "$gem_path" data.tar.gz | tar -tzf - | grep -Fx runtime/templates/secrets/.gitkeep >/dev/null
}

validate_gem_install() {
  local gem_home="$validation_dir/gem-home"
  local bin_dir="$validation_dir/gem-bin"
  local smoke_project="$validation_dir/gem-smoke-project"

  install -d "$gem_home" "$bin_dir"
  GEM_HOME="$gem_home" GEM_PATH="$gem_home" \
    "$gem_cmd" install --local --install-dir "$gem_home" --bindir "$bin_dir" --no-document "$gem_path" >/dev/null
  test -x "$bin_dir/sshfling"
  GEM_HOME="$gem_home" GEM_PATH="$gem_home" \
    "$ruby_cmd" -e 'require "sshfling"; abort unless SSHFling::VERSION == ARGV[0] && File.file?(SSHFling.runtime_path) && SSHFling.run(["--version"]) == 0' "$version"
  GEM_HOME="$gem_home" GEM_PATH="$gem_home" "$bin_dir/sshfling" --version | grep -Fx "sshfling $version" >/dev/null
  GEM_HOME="$gem_home" GEM_PATH="$gem_home" "$bin_dir/sshfling" --project-dir "$smoke_project" doctor >/dev/null
  GEM_HOME="$gem_home" GEM_PATH="$gem_home" "$bin_dir/sshfling" init "$smoke_project" --force --session-seconds 60 >/dev/null
  test -x "$smoke_project/scripts/install-local.sh"
  test -x "$smoke_project/scripts/uninstall-local.sh"
  test -x "$smoke_project/native/sshfling-linux-account"
  test -x "$smoke_project/native/sshfling-unix-identity"
  test -x "$smoke_project/production/sshfling-session"
  test -f "$smoke_project/secrets/.gitkeep"

  GEM_HOME="$gem_home" GEM_PATH="$gem_home" \
    "$gem_cmd" uninstall --all --executables --ignore-dependencies --bindir "$bin_dir" sshfling >/dev/null
  test ! -e "$bin_dir/sshfling"
  test ! -d "$gem_home/gems/sshfling-$version"
}

validate_bundler_install() {
  local app_dir="$validation_dir/bundler-app"
  local bundle_path="$validation_dir/bundle"
  local smoke_project="$validation_dir/bundler-smoke-project"

  install -d "$app_dir"
  "$ruby_cmd" -e '
path = ARGV[0].gsub("\\\\", "/")
File.write(ARGV[1], "source \"https://rubygems.org\"\n\ngem \"sshfling\", path: #{path.inspect}\n")
' "$package_dir" "$app_dir/Gemfile"
  (
    cd "$app_dir"
    SSHFLING_GEM_VERSION="$version" BUNDLE_PATH="$bundle_path" BUNDLE_DISABLE_SHARED_GEMS=true \
      "$bundle_cmd" install --local >/dev/null
    SSHFLING_GEM_VERSION="$version" BUNDLE_PATH="$bundle_path" BUNDLE_DISABLE_SHARED_GEMS=true \
      "$bundle_cmd" exec "$ruby_cmd" -e 'require "sshfling"; abort unless SSHFling.run(["--version"]) == 0'
    SSHFLING_GEM_VERSION="$version" BUNDLE_PATH="$bundle_path" BUNDLE_DISABLE_SHARED_GEMS=true \
      "$bundle_cmd" exec sshfling --version | grep -Fx "sshfling $version" >/dev/null
    SSHFLING_GEM_VERSION="$version" BUNDLE_PATH="$bundle_path" BUNDLE_DISABLE_SHARED_GEMS=true \
      "$bundle_cmd" exec sshfling init "$smoke_project" --force --session-seconds 60 >/dev/null
  )
  test -x "$smoke_project/scripts/install-local.sh"
  test -x "$smoke_project/native/sshfling-linux-account"
  test -x "$smoke_project/native/sshfling-unix-identity"
  test -f "$smoke_project/secrets/.gitkeep"

  rm -rf "$bundle_path" "$app_dir/.bundle" "$app_dir/Gemfile.lock"
  test ! -e "$bundle_path"
}

rm -rf "$build_root"
install -d "$build_root" "$validation_dir" "$dist_dir"
rm -f "$gem_path"

copy_ruby_project
validate_ruby_project
copy_and_validate_gem
validate_gem_install
validate_bundler_install

printf '%s\n' "$gem_path"
