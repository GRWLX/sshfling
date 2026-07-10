#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=packaging/version.sh
source "$repo_root/packaging/version.sh"
version="$(assert_sshfling_version_matches_source "${SSHFLING_VERSION:-}" "$repo_root")"

dotnet_cmd="${DOTNET:-dotnet}"
if ! command -v "$dotnet_cmd" >/dev/null 2>&1; then
  echo "dotnet SDK is required to build the SSHFling .NET global tool package." >&2
  echo "Install .NET 10 SDK or set DOTNET to a dotnet executable." >&2
  exit 127
fi
dotnet_resolved="$(command -v "$dotnet_cmd")"
if command -v readlink >/dev/null 2>&1; then
  dotnet_resolved="$(readlink -f "$dotnet_resolved")"
fi
dotnet_root="$(cd "$(dirname "$dotnet_resolved")" && pwd)"

tool_project="$repo_root/packaging/dotnet/SSHFling.Tool/SSHFling.Tool.csproj"
library_project="$repo_root/packaging/dotnet/SSHFling/SSHFling.csproj"
build_root="$repo_root/build/dotnet"
dist_dir="$repo_root/dist"
home_dir="$build_root/home"
nuget_dir="$build_root/nuget-packages"
validation_dir="$build_root/validation"
tool_package_path="$dist_dir/SSHFling.Tool.$version.nupkg"
library_package_path="$dist_dir/SSHFling.$version.nupkg"

export DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_NOLOGO=1
export DOTNET_ROOT="${DOTNET_ROOT:-$dotnet_root}"
export DOTNET_ROOT_X64="${DOTNET_ROOT_X64:-$DOTNET_ROOT}"
export DOTNET_CLI_HOME="$home_dir"
export NUGET_PACKAGES="$nuget_dir"
export NUGET_XMLDOC_MODE=skip

validate_library_consumer() {
  local language="$1"
  local source_dir="$2"
  local project_name="$3"
  local consumer_dir="$validation_dir/library-consumer-$language"
  local consumer_project="$consumer_dir/$project_name"
  local smoke_project="$validation_dir/library-smoke-$language"

  cp -R "$source_dir" "$consumer_dir"
  "$dotnet_cmd" restore "$consumer_project" \
    --source "$dist_dir" \
    -p:SSHFlingVersion="$version"
  "$dotnet_cmd" run \
    --project "$consumer_project" \
    --configuration Release \
    --no-restore \
    -p:SSHFlingVersion="$version" \
    -- "$version" --version | grep -Fx "sshfling $version" >/dev/null
  "$dotnet_cmd" run \
    --project "$consumer_project" \
    --configuration Release \
    --no-restore \
    -p:SSHFlingVersion="$version" \
    -- "$version" init "$smoke_project" --force --session-seconds 60 >/dev/null
  test -x "$smoke_project/native/sshfling-linux-account"
  test -x "$smoke_project/native/sshfling-unix-identity"
  test -x "$smoke_project/production/sshfling-login-shell"
  "$dotnet_cmd" remove "$consumer_project" package SSHFling
  if grep -Fq 'PackageReference Include="SSHFling"' "$consumer_project"; then
    echo "dotnet remove left the SSHFling library PackageReference in the $language consumer." >&2
    exit 1
  fi
}

rm -rf "$build_root"
install -d "$home_dir" "$nuget_dir" "$validation_dir" "$dist_dir"
rm -f "$tool_package_path" "$library_package_path"

"$dotnet_cmd" pack "$tool_project" \
  --configuration Release \
  --output "$dist_dir" \
  -p:Version="$version" \
  -p:PackageVersion="$version" \
  -p:ContinuousIntegrationBuild=true

"$dotnet_cmd" pack "$library_project" \
  --configuration Release \
  --output "$dist_dir" \
  -p:Version="$version" \
  -p:PackageVersion="$version" \
  -p:ContinuousIntegrationBuild=true

if [[ ! -s "$tool_package_path" ]]; then
  echo "NuGet global tool package was not created: $tool_package_path" >&2
  exit 1
fi
if [[ ! -s "$library_package_path" ]]; then
  echo "NuGet library package was not created: $library_package_path" >&2
  exit 1
fi

python3 - "$tool_package_path" "$library_package_path" <<'PY'
import sys
import zipfile

packages = {
    sys.argv[1]: {
    "tools/net10.0/any/templates/native/sshfling-linux-account",
    "tools/net10.0/any/templates/native/sshfling-unix-identity",
    "tools/net10.0/any/templates/production/sshfling-login-shell",
    "tools/net10.0/any/templates/systemd/sshfling-prune.service",
    "tools/net10.0/any/templates/systemd/sshfling-prune.timer",
    },
    sys.argv[2]: {
        "lib/net10.0/SSHFling.dll",
        "lib/net10.0/SSHFling.xml",
        "LICENSE",
        "README.md",
    },
}
for package, required in packages.items():
    with zipfile.ZipFile(package) as archive:
        names = set(archive.namelist())
    missing = sorted(required - names)
    if missing:
        for path in missing:
            print(f"NuGet package is missing required path: {path}", file=sys.stderr)
        raise SystemExit(1)
PY

if [[ "${SSHFLING_DOTNET_SKIP_VALIDATE:-}" != "1" ]]; then
  "$dotnet_cmd" tool install SSHFling.Tool \
    --tool-path "$validation_dir/tool" \
    --add-source "$dist_dir" \
    --version "$version" \
    --ignore-failed-sources
  "$validation_dir/tool/sshfling" --version | grep -Fx "sshfling $version" >/dev/null
  smoke_project="$validation_dir/smoke-project"
  "$validation_dir/tool/sshfling" --project-dir "$smoke_project" doctor >/dev/null
  "$validation_dir/tool/sshfling" init "$smoke_project" --force --session-seconds 60 >/dev/null
  test -x "$smoke_project/scripts/install-local.sh"
  test -x "$smoke_project/scripts/uninstall-local.sh"
  test -x "$smoke_project/native/sshfling-linux-account"
  test -x "$smoke_project/native/sshfling-unix-identity"
  test -x "$smoke_project/production/sshfling-login-shell"
  test -x "$smoke_project/production/sshfling-session"
  test -f "$smoke_project/secrets/.gitkeep"

  validate_library_consumer \
    csharp \
    "$repo_root/packaging/dotnet/SSHFling.Consumer" \
    SSHFling.Consumer.csproj
  validate_library_consumer \
    visual-basic \
    "$repo_root/packaging/dotnet/SSHFling.Consumer.VB" \
    SSHFling.Consumer.VB.vbproj
  validate_library_consumer \
    fsharp \
    "$repo_root/packaging/dotnet/SSHFling.Consumer.FSharp" \
    SSHFling.Consumer.FSharp.fsproj

  "$dotnet_cmd" tool uninstall SSHFling.Tool --tool-path "$validation_dir/tool"
  test ! -e "$validation_dir/tool/sshfling"
fi

printf '%s\n' "$tool_package_path"
printf '%s\n' "$library_package_path"
