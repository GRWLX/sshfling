#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=packaging/version.sh
source "$repo_root/packaging/version.sh"
version="$(assert_sshfling_version_matches_source "${SSHFLING_VERSION:-}" "$repo_root")"

mvn_cmd="${MAVEN:-mvn}"
gradle_cmd="${GRADLE:-$repo_root/packaging/java/gradlew}"
if ! command -v "$mvn_cmd" >/dev/null 2>&1; then
  echo "Maven is required to build the SSHFling Java package." >&2
  echo "Install Maven and JDK 11 or newer, or set MAVEN to a Maven executable." >&2
  exit 127
fi
if [[ ! -x "$gradle_cmd" ]] && ! command -v "$gradle_cmd" >/dev/null 2>&1; then
  echo "The pinned Gradle wrapper is required to validate the SSHFling Java library." >&2
  echo "Set GRADLE to another Gradle 9.6-compatible executable if needed." >&2
  exit 127
fi
if ! command -v java >/dev/null 2>&1; then
  echo "A JDK/JRE is required to validate the SSHFling Java package." >&2
  exit 127
fi

dist_dir="$repo_root/dist"
build_root="$repo_root/build/java"
project_dir="$build_root/project"
maven_repo="${SSHFLING_MAVEN_REPO_LOCAL:-$build_root/m2}"
gradle_repo="$build_root/gradle-repository"
settings_file="${MAVEN_SETTINGS:-}"
jar_path="$dist_dir/sshfling-cli-$version.jar"
sources_jar_path="$dist_dir/sshfling-cli-$version-sources.jar"
javadoc_jar_path="$dist_dir/sshfling-cli-$version-javadoc.jar"
pom_path="$dist_dir/sshfling-cli-$version.pom"
deploy="${SSHFLING_JAVA_DEPLOY:-}"
registry_url="${SSHFLING_JAVA_REGISTRY_URL:-https://maven.pkg.github.com/${GITHUB_REPOSITORY:-GRWLX/sshfling}}"

export LC_ALL=C
export TZ=UTC
export GRADLE_USER_HOME="${SSHFLING_GRADLE_USER_HOME:-$build_root/gradle-home}"
umask 022

source_date_epoch="${SOURCE_DATE_EPOCH:-}"
if [[ -z "$source_date_epoch" ]]; then
  source_date_epoch="$(git -C "$repo_root" log -1 --format=%ct HEAD 2>/dev/null || printf '1700000000')"
fi
if [[ ! "$source_date_epoch" =~ ^[0-9]+$ ]]; then
  echo "SOURCE_DATE_EPOCH must be an integer Unix timestamp." >&2
  exit 2
fi
if date -u -d "@$source_date_epoch" "+%Y-%m-%dT%H:%M:%SZ" >/dev/null 2>&1; then
  output_timestamp="$(date -u -d "@$source_date_epoch" "+%Y-%m-%dT%H:%M:%SZ")"
elif date -u -r "$source_date_epoch" "+%Y-%m-%dT%H:%M:%SZ" >/dev/null 2>&1; then
  output_timestamp="$(date -u -r "$source_date_epoch" "+%Y-%m-%dT%H:%M:%SZ")"
else
  echo "date must support either GNU -d @epoch or BSD -r epoch." >&2
  exit 127
fi

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
  sed \
    -e "s|\${revision}|$version|g" \
    -e "s|\${github.package.registry.url}|$registry_url|g" \
    "$repo_root/packaging/java/pom.xml" >"$project_dir/pom.xml"
  cp "$repo_root/packaging/java/build.gradle.kts" "$project_dir/build.gradle.kts"
  cp "$repo_root/packaging/java/settings.gradle.kts" "$project_dir/settings.gradle.kts"
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
          templates/native/sshfling-linux-account|\
          templates/native/sshfling-unix-identity|\
          templates/production/sshfling-login-shell|\
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

validate_maven_language_consumer() {
  local language="$1"
  local main_class="$2"
  local class_file="$3"
  local consumer_dir="$build_root/validation/$language-consumer"
  local smoke_project="$build_root/validation/$language-smoke-project"

  cp -R "$repo_root/packaging/java/consumers/$language" "$consumer_dir"
  "$mvn_cmd" -B \
    -f "$consumer_dir/pom.xml" \
    -Dmaven.repo.local="$maven_repo" \
    -Dsshfling.version="$version" \
    -Dstyle.color=never \
    package
  test -s "$consumer_dir/target/classes/$class_file"
  "$mvn_cmd" -B -q \
    -f "$consumer_dir/pom.xml" \
    -Dmaven.repo.local="$maven_repo" \
    -Dsshfling.version="$version" \
    -Dstyle.color=never \
    -Dexec.mainClass="$main_class" \
    -Dexec.args=--version \
    exec:java | grep -Fx "sshfling $version" >/dev/null
  "$mvn_cmd" -B -q \
    -f "$consumer_dir/pom.xml" \
    -Dmaven.repo.local="$maven_repo" \
    -Dsshfling.version="$version" \
    -Dstyle.color=never \
    -Dexec.mainClass="$main_class" \
    -Dexec.args="init $smoke_project --force --session-seconds 60" \
    exec:java >/dev/null
  test -x "$smoke_project/native/sshfling-linux-account"
  test -x "$smoke_project/native/sshfling-unix-identity"
}

validate_gradle_language_consumer() {
  local language="$1"
  local class_file="$2"
  local consumer_dir="$build_root/validation/$language-gradle-consumer"
  local smoke_project="$build_root/validation/$language-gradle-smoke-project"

  cp -R "$repo_root/packaging/java/consumers/$language-gradle" "$consumer_dir"
  "$gradle_cmd" \
    --no-daemon \
    --console=plain \
    -p "$consumer_dir" \
    -PsshflingVersion="$version" \
    -PsshflingRepository="$gradle_repo" \
    run --args=--version | grep -Fx "sshfling $version" >/dev/null
  test -s "$consumer_dir/$class_file"
  javap -verbose "$consumer_dir/$class_file" | grep -F "major version: 55" >/dev/null
  "$gradle_cmd" \
    --no-daemon \
    --console=plain \
    -p "$consumer_dir" \
    -PsshflingVersion="$version" \
    -PsshflingRepository="$gradle_repo" \
    run --args="init $smoke_project --force --session-seconds 60" >/dev/null
  test -x "$smoke_project/native/sshfling-linux-account"
  test -x "$smoke_project/native/sshfling-unix-identity"
}

validate_clojure_maven_consumer() {
  local consumer_dir="$build_root/validation/clojure-consumer"
  local smoke_project="$build_root/validation/clojure-smoke-project"
  local namespace="io.sshfling.validation.clojure-consumer"

  cp -R "$repo_root/packaging/java/consumers/clojure" "$consumer_dir"
  "$mvn_cmd" -B \
    -f "$consumer_dir/pom.xml" \
    -Dmaven.repo.local="$maven_repo" \
    -Dsshfling.version="$version" \
    -Dstyle.color=never \
    verify
  test -s "$consumer_dir/target/classes/io/sshfling/validation/clojure_consumer.clj"
  "$mvn_cmd" -B -q \
    -f "$consumer_dir/pom.xml" \
    -Dmaven.repo.local="$maven_repo" \
    -Dsshfling.version="$version" \
    -Dstyle.color=never \
    -Dexec.mainClass=clojure.main \
    -Dexec.args="-m $namespace --version" \
    exec:java | grep -Fx "sshfling $version" >/dev/null
  "$mvn_cmd" -B -q \
    -f "$consumer_dir/pom.xml" \
    -Dmaven.repo.local="$maven_repo" \
    -Dsshfling.version="$version" \
    -Dstyle.color=never \
    -Dexec.mainClass=clojure.main \
    -Dexec.args="-m $namespace init $smoke_project --force --session-seconds 60" \
    exec:java >/dev/null
  test -x "$smoke_project/native/sshfling-linux-account"
  test -x "$smoke_project/native/sshfling-unix-identity"
}

validate_clojure_gradle_consumer() {
  local consumer_dir="$build_root/validation/clojure-gradle-consumer"
  local smoke_project="$build_root/validation/clojure-gradle-smoke-project"

  cp -R "$repo_root/packaging/java/consumers/clojure-gradle" "$consumer_dir"
  "$gradle_cmd" \
    --no-daemon \
    --console=plain \
    -p "$consumer_dir" \
    -PsshflingVersion="$version" \
    -PsshflingRepository="$gradle_repo" \
    clean check
  test -s "$consumer_dir/build/resources/main/io/sshfling/validation/clojure_gradle_consumer.clj"
  "$gradle_cmd" \
    --no-daemon \
    --console=plain \
    -p "$consumer_dir" \
    -PsshflingVersion="$version" \
    -PsshflingRepository="$gradle_repo" \
    run --args=--version | grep -Fx "sshfling $version" >/dev/null
  "$gradle_cmd" \
    --no-daemon \
    --console=plain \
    -p "$consumer_dir" \
    -PsshflingVersion="$version" \
    -PsshflingRepository="$gradle_repo" \
    run --args="init $smoke_project --force --session-seconds 60" >/dev/null
  test -x "$smoke_project/native/sshfling-linux-account"
  test -x "$smoke_project/native/sshfling-unix-identity"
}

validate_java_package() {
  local validation_dir="$build_root/validation"
  local smoke_project="$validation_dir/smoke-project"
  local gradle_jar="$project_dir/build/libs/sshfling-cli-$version.jar"
  local maven_consumer="$validation_dir/maven-consumer"
  local gradle_consumer="$validation_dir/gradle-consumer"
  local gradle_publication="$gradle_repo/io/sshfling/sshfling-cli/$version"
  local jar_extract="$validation_dir/jar-extract"

  rm -rf "$validation_dir"
  install -d "$validation_dir"
  java -jar "$jar_path" --version | grep -Fx "sshfling $version" >/dev/null
  java -jar "$jar_path" --project-dir "$smoke_project" doctor >/dev/null
  java -jar "$jar_path" init "$smoke_project" --force --session-seconds 60 >/dev/null
  test -x "$smoke_project/scripts/install-local.sh"
  test -x "$smoke_project/scripts/uninstall-local.sh"
  test -x "$smoke_project/native/sshfling-linux-account"
  test -x "$smoke_project/native/sshfling-unix-identity"
  test -x "$smoke_project/production/sshfling-login-shell"
  test -x "$smoke_project/production/sshfling-session"
  test -f "$smoke_project/secrets/.gitkeep"
  jar tf "$jar_path" | grep -Fx "sshfling/sshfling.py" >/dev/null
  jar tf "$jar_path" | grep -Fx "sshfling/resource-manifest.txt" >/dev/null
  jar tf "$jar_path" | grep -Fx "sshfling/templates/systemd/sshfling-prune.service" >/dev/null
  jar tf "$jar_path" | grep -Fx "sshfling/templates/systemd/sshfling-prune.timer" >/dev/null
  jar tf "$jar_path" | grep -Fx "sshfling/templates/native/sshfling-linux-account" >/dev/null
  jar tf "$jar_path" | grep -Fx "sshfling/templates/production/sshfling-login-shell" >/dev/null
  install -d "$jar_extract"
  (cd "$jar_extract" && jar xf "$jar_path" sshfling/resource-manifest.txt)
  grep -Fx "0755 templates/native/sshfling-linux-account" "$jar_extract/sshfling/resource-manifest.txt" >/dev/null
  grep -Fx "0755 templates/native/sshfling-unix-identity" "$jar_extract/sshfling/resource-manifest.txt" >/dev/null
  grep -Fx "0755 templates/production/sshfling-login-shell" "$jar_extract/sshfling/resource-manifest.txt" >/dev/null
  jar tf "$javadoc_jar_path" | grep -Fx "io/sshfling/cli/SSHFling.html" >/dev/null

  test -s "$gradle_jar"
  java -jar "$gradle_jar" --version | grep -Fx "sshfling $version" >/dev/null
  jar tf "$gradle_jar" | grep -Fx "sshfling/resource-manifest.txt" >/dev/null
  test -s "$gradle_publication/sshfling-cli-$version.jar"
  test -s "$gradle_publication/sshfling-cli-$version-sources.jar"
  test -s "$gradle_publication/sshfling-cli-$version-javadoc.jar"
  test -s "$gradle_publication/sshfling-cli-$version.pom"
  test -s "$gradle_publication/sshfling-cli-$version.module"
  java -jar "$gradle_publication/sshfling-cli-$version.jar" --version | grep -Fx "sshfling $version" >/dev/null

  cp -R "$repo_root/packaging/java/consumers/maven" "$maven_consumer"
  "$mvn_cmd" -B \
    -f "$maven_consumer/pom.xml" \
    -Dmaven.repo.local="$maven_repo" \
    -Dsshfling.version="$version" \
    package
  java -cp "$maven_consumer/target/classes:$jar_path" \
    io.sshfling.validation.MavenConsumer --version | grep -Fx "sshfling $version" >/dev/null

  validate_maven_language_consumer \
    kotlin \
    io.sshfling.validation.KotlinConsumer \
    io/sshfling/validation/KotlinConsumer.class
  validate_maven_language_consumer \
    scala \
    io.sshfling.validation.ScalaConsumer \
    io/sshfling/validation/ScalaConsumer.class
  validate_maven_language_consumer \
    groovy \
    io.sshfling.validation.GroovyConsumer \
    io/sshfling/validation/GroovyConsumer.class
  validate_clojure_maven_consumer

  cp -R "$repo_root/packaging/java/consumers/gradle" "$gradle_consumer"
  "$gradle_cmd" \
    --no-daemon \
    --console=plain \
    -p "$gradle_consumer" \
    -PsshflingVersion="$version" \
    -PsshflingRepository="$gradle_repo" \
    run --args=--version | grep -Fx "sshfling $version" >/dev/null

  validate_gradle_language_consumer \
    kotlin \
    build/classes/kotlin/main/io/sshfling/validation/KotlinGradleConsumer.class
  validate_gradle_language_consumer \
    scala \
    build/classes/scala/main/io/sshfling/validation/ScalaGradleConsumer.class
  validate_gradle_language_consumer \
    groovy \
    build/classes/groovy/main/io/sshfling/validation/GroovyGradleConsumer.class
  validate_clojure_gradle_consumer
}

rm -rf "$build_root"
install -d "$build_root" "$maven_repo" "$dist_dir"
rm -f "$jar_path" "$sources_jar_path" "$javadoc_jar_path" "$pom_path"

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
  "$mvn_cmd" "${maven_args[@]}" clean install
fi

"$gradle_cmd" \
  --no-daemon \
  --console=plain \
  -p "$project_dir" \
  -Prevision="$version" \
  -PpublicationRepository="$gradle_repo" \
  clean build publish

cp "$project_dir/target/sshfling-cli-$version.jar" "$jar_path"
cp "$project_dir/target/sshfling-cli-$version-sources.jar" "$sources_jar_path"
cp "$project_dir/target/sshfling-cli-$version-javadoc.jar" "$javadoc_jar_path"
write_dist_pom
validate_java_package

printf '%s\n' "$jar_path"
printf '%s\n' "$sources_jar_path"
printf '%s\n' "$javadoc_jar_path"
printf '%s\n' "$pom_path"
