#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=packaging/version.sh
source "$repo_root/packaging/version.sh"
version="$(assert_sshfling_version_matches_source "${SSHFLING_VERSION:-}" "$repo_root")"

mvn_cmd="${MAVEN:-mvn}"
if ! command -v "$mvn_cmd" >/dev/null 2>&1; then
  echo "Maven is required to build the SSHFling Java package." >&2
  echo "Install Maven and JDK 11 or newer, or set MAVEN to a Maven executable." >&2
  exit 127
fi
if ! command -v java >/dev/null 2>&1; then
  echo "A JDK/JRE is required to validate the SSHFling Java package." >&2
  exit 127
fi

dist_dir="$repo_root/dist"
build_root="$repo_root/build/java"
project_dir="$build_root/project"
maven_repo="$build_root/m2"
settings_file="${MAVEN_SETTINGS:-}"
jar_path="$dist_dir/sshfling-cli-$version.jar"
sources_jar_path="$dist_dir/sshfling-cli-$version-sources.jar"
pom_path="$dist_dir/sshfling-cli-$version.pom"
deploy="${SSHFLING_JAVA_DEPLOY:-}"
registry_url="${SSHFLING_JAVA_REGISTRY_URL:-https://maven.pkg.github.com/${GITHUB_REPOSITORY:-GRWLX/sshfling}}"

export LC_ALL=C
export TZ=UTC
umask 022

source_date_epoch="${SOURCE_DATE_EPOCH:-}"
if [[ -z "$source_date_epoch" ]]; then
  source_date_epoch="$(git -C "$repo_root" log -1 --format=%ct HEAD 2>/dev/null || printf '1700000000')"
fi
if [[ ! "$source_date_epoch" =~ ^[0-9]+$ ]]; then
  echo "SOURCE_DATE_EPOCH must be an integer Unix timestamp." >&2
  exit 2
fi
output_timestamp="$(
  python3 - "$source_date_epoch" <<'PY'
import datetime as dt
import sys

epoch = int(sys.argv[1])
print(dt.datetime.fromtimestamp(epoch, tz=dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))
PY
)"

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

write_maven_settings() {
  local user="${SSHFLING_JAVA_MAVEN_USER:-${GITHUB_ACTOR:-}}"
  local token="${SSHFLING_JAVA_MAVEN_TOKEN:-${GITHUB_TOKEN:-}}"

  if [[ -n "$settings_file" ]]; then
    return 0
  fi
  if [[ -z "$user" || -z "$token" ]]; then
    echo "Java deploy requires MAVEN_SETTINGS or GITHUB_ACTOR/GITHUB_TOKEN." >&2
    exit 2
  fi

  settings_file="$build_root/settings.xml"
  cat >"$settings_file" <<SETTINGS
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.0.0 https://maven.apache.org/xsd/settings-1.0.0.xsd">
  <servers>
    <server>
      <id>github</id>
      <username>${user}</username>
      <password>${token}</password>
    </server>
  </servers>
</settings>
SETTINGS
  chmod 0600 "$settings_file"
}

copy_java_project() {
  rm -rf "$project_dir"
  install -d "$project_dir/src/main/java" "$project_dir/src/main/resources/sshfling"
  cp "$repo_root/packaging/java/pom.xml" "$project_dir/pom.xml"
  cp -R "$repo_root/packaging/java/src/main/java/." "$project_dir/src/main/java/"
  install -m 0644 "$repo_root/bin/sshfling" "$project_dir/src/main/resources/sshfling/sshfling.py"

  # shellcheck source=packaging/copy-templates.sh
  source "$repo_root/packaging/copy-templates.sh"
  copy_sshfling_templates "$repo_root" "$project_dir/src/main/resources/sshfling/templates"
}

write_resource_manifest() {
  local resources="$project_dir/src/main/resources/sshfling"
  local manifest="$resources/resource-manifest.txt"

  {
    printf '0755 sshfling.py\n'
    (
      cd "$resources"
      find templates -type f -print | sort | while IFS= read -r relative; do
        case "$relative" in
          templates/production/sshfling-session|\
          templates/scripts/create-network.sh|\
          templates/scripts/generate-ssh-key.sh|\
          templates/scripts/install-local.sh|\
          templates/scripts/uninstall-local.sh|\
          templates/ssh-client/entrypoint.sh|\
          templates/ssh-server/entrypoint.sh|\
          templates/ssh-server/limited-session.sh)
            printf '0755 %s\n' "$relative"
            ;;
          *)
            printf '0644 %s\n' "$relative"
            ;;
        esac
      done
    )
  } >"$manifest"
}

write_dist_pom() {
  sed \
    -e "s|\${revision}|$version|g" \
    -e "s|\${github.package.registry.url}|$registry_url|g" \
    "$repo_root/packaging/java/pom.xml" >"$pom_path"
}

validate_java_package() {
  local validation_dir="$build_root/validation"
  local smoke_project="$validation_dir/smoke-project"

  rm -rf "$validation_dir"
  install -d "$validation_dir"
  java -jar "$jar_path" --version | grep -Fx "sshfling $version" >/dev/null
  java -jar "$jar_path" --project-dir "$smoke_project" doctor >/dev/null
  java -jar "$jar_path" init "$smoke_project" --force --session-seconds 60 >/dev/null
  test -x "$smoke_project/scripts/install-local.sh"
  test -x "$smoke_project/scripts/uninstall-local.sh"
  test -x "$smoke_project/production/sshfling-session"
  test -f "$smoke_project/secrets/.gitkeep"
  jar tf "$jar_path" | grep -Fx "sshfling/sshfling.py" >/dev/null
  jar tf "$jar_path" | grep -Fx "sshfling/resource-manifest.txt" >/dev/null
}

rm -rf "$build_root"
install -d "$build_root" "$maven_repo" "$dist_dir"
rm -f "$jar_path" "$sources_jar_path" "$pom_path"

copy_java_project
write_resource_manifest

maven_args=(
  -B
  -f "$project_dir/pom.xml"
  -Dmaven.repo.local="$maven_repo"
  -Drevision="$version"
  -Dgithub.package.registry.url="$registry_url"
  -Dproject.build.outputTimestamp="$output_timestamp"
)

if is_truthy "$deploy"; then
  write_maven_settings
  "$mvn_cmd" "${maven_args[@]}" -s "$settings_file" clean deploy
else
  "$mvn_cmd" "${maven_args[@]}" clean verify
fi

cp "$project_dir/target/sshfling-cli-$version.jar" "$jar_path"
cp "$project_dir/target/sshfling-cli-$version-sources.jar" "$sources_jar_path"
write_dist_pom
validate_java_package

printf '%s\n' "$jar_path"
printf '%s\n' "$sources_jar_path"
printf '%s\n' "$pom_path"
