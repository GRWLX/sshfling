#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=packaging/version.sh
source "$repo_root/packaging/version.sh"
version="$(assert_sshfling_version_matches_source "${SSHFLING_VERSION:-}" "$repo_root")"

php_cmd="${PHP:-php}"
composer_cmd="${COMPOSER:-composer}"
if ! command -v "$php_cmd" >/dev/null 2>&1; then
  echo "PHP 8.1 or newer is required to build the SSHFling Composer package." >&2
  exit 127
fi
if ! "$php_cmd" -r 'exit(PHP_VERSION_ID < 80100 ? 1 : 0);'; then
  echo "PHP 8.1 or newer is required to build the SSHFling Composer package." >&2
  exit 2
fi
if ! command -v "$composer_cmd" >/dev/null 2>&1; then
  echo "Composer is required to build the SSHFling PHP package." >&2
  exit 127
fi

dist_dir="$repo_root/dist"
build_root="$repo_root/build/php"
package_dir="$build_root/package"
validation_dir="$build_root/validation"
archive_path="$dist_dir/sshfling-php-$version.zip"

export LC_ALL=C
export TZ=UTC
export COMPOSER_HOME="$build_root/composer-home"
export COMPOSER_CACHE_DIR="$build_root/composer-cache"
export COMPOSER_NO_INTERACTION=1
export COMPOSER_ALLOW_SUPERUSER=1
umask 022

copy_php_project() {
  rm -rf "$package_dir"
  install -d "$package_dir/src" "$package_dir/bin" "$package_dir/runtime"
  install -m 0644 "$repo_root/packaging/php/composer.json" "$package_dir/composer.json"
  install -m 0644 "$repo_root/packaging/php/src/SSHFling.php" "$package_dir/src/SSHFling.php"
  install -m 0755 "$repo_root/packaging/php/bin/sshfling" "$package_dir/bin/sshfling"
  install -m 0644 "$repo_root/LICENSE" "$package_dir/LICENSE"
  install -m 0644 "$repo_root/README.md" "$package_dir/README.md"
  install -m 0755 "$repo_root/bin/sshfling" "$package_dir/runtime/sshfling.py"

  # shellcheck source=packaging/copy-templates.sh
  source "$repo_root/packaging/copy-templates.sh"
  copy_sshfling_templates "$repo_root" "$package_dir/runtime/templates"

}

validate_php_project() {
  "$php_cmd" -l "$package_dir/src/SSHFling.php" >/dev/null
  "$php_cmd" -l "$package_dir/bin/sshfling" >/dev/null
  "$composer_cmd" validate --strict "$package_dir/composer.json"
  "$php_cmd" -r '
$path = $argv[1];
$metadata = json_decode(file_get_contents($path), true, 512, JSON_THROW_ON_ERROR);
$metadata["version"] = $argv[2];
file_put_contents($path, json_encode($metadata, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR) . PHP_EOL);
' "$package_dir/composer.json" "$version"
  "$composer_cmd" dump-autoload --working-dir "$package_dir" --classmap-authoritative --no-dev >/dev/null
  "$php_cmd" -r '
require $argv[1];
$class = "GRWLX\\SSHFling\\SSHFling";
if (!class_exists($class) || !is_file($class::runtimePath()) || !is_dir($class::templateDir())) {
    exit(1);
}
if ($class::run(["--version"]) !== 0) {
    exit(1);
}
' "$package_dir/vendor/autoload.php"
  rm -rf "$package_dir/vendor"
}

build_archive() {
  rm -f "$archive_path"
  "$composer_cmd" archive \
    --working-dir "$package_dir" \
    --format zip \
    --dir "$dist_dir" \
    --file "sshfling-php-$version" >/dev/null

  unzip -Z1 "$archive_path" | grep -Eq '(^|/)composer\.json$'
  unzip -Z1 "$archive_path" | grep -Eq '(^|/)src/SSHFling\.php$'
  unzip -Z1 "$archive_path" | grep -Eq '(^|/)bin/sshfling$'
  unzip -Z1 "$archive_path" | grep -Eq '(^|/)runtime/sshfling\.py$'
  unzip -Z1 "$archive_path" | grep -Eq '(^|/)runtime/templates/systemd/sshfling-prune\.timer$'
  unzip -Z1 "$archive_path" | grep -Eq '(^|/)runtime/templates/native/sshfling-linux-account$'
  unzip -Z1 "$archive_path" | grep -Eq '(^|/)runtime/templates/native/sshfling-unix-identity$'
  unzip -Z1 "$archive_path" | grep -Eq '(^|/)runtime/templates/production/sshfling-login-shell$'
  unzip -Z1 "$archive_path" | grep -Eq '(^|/)runtime/templates/secrets/\.gitkeep$'
}

validate_composer_install() {
  local artifact_dir="$validation_dir/artifacts"
  local app_dir="$validation_dir/app"
  local smoke_project="$validation_dir/smoke-project"

  install -d "$artifact_dir" "$app_dir"
  cp "$archive_path" "$artifact_dir/"
  "$php_cmd" -r '
$path = $argv[1];
$artifactDir = str_replace("\\", "/", $argv[2]);
$metadata = [
    "repositories" => [["type" => "artifact", "url" => $artifactDir]],
    "require" => ["grwlx/sshfling" => $argv[3]],
    "config" => ["allow-plugins" => false],
];
file_put_contents($path, json_encode($metadata, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR) . PHP_EOL);
' "$app_dir/composer.json" "$artifact_dir" "$version"

  "$composer_cmd" install --working-dir "$app_dir" --no-dev --no-plugins --no-scripts --prefer-dist >/dev/null
  test -x "$app_dir/vendor/bin/sshfling"
  "$php_cmd" -r '
require $argv[1];
$class = "GRWLX\\SSHFling\\SSHFling";
exit(
    class_exists($class) &&
    is_file($class::runtimePath()) &&
    $class::run(["--version"]) === 0
        ? 0
        : 1
);
' "$app_dir/vendor/autoload.php"
  "$app_dir/vendor/bin/sshfling" --version | grep -Fx "sshfling $version" >/dev/null
  "$app_dir/vendor/bin/sshfling" --project-dir "$smoke_project" doctor >/dev/null
  "$app_dir/vendor/bin/sshfling" init "$smoke_project" --force --session-seconds 60 >/dev/null
  test -x "$smoke_project/scripts/install-local.sh"
  test -x "$smoke_project/scripts/uninstall-local.sh"
  test -x "$smoke_project/native/sshfling-linux-account"
  test -x "$smoke_project/native/sshfling-unix-identity"
  test -x "$smoke_project/production/sshfling-login-shell"
  test -x "$smoke_project/production/sshfling-session"
  test -f "$smoke_project/secrets/.gitkeep"

  "$composer_cmd" remove --working-dir "$app_dir" --no-plugins --no-scripts grwlx/sshfling >/dev/null
  test ! -e "$app_dir/vendor/bin/sshfling"
  test ! -e "$app_dir/vendor/grwlx/sshfling"
}

rm -rf "$build_root"
install -d "$build_root" "$validation_dir" "$dist_dir"

copy_php_project
validate_php_project
build_archive
validate_composer_install

printf '%s\n' "$archive_path"
