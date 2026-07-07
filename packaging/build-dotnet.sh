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
dotnet_root="$(cd "$(dirname "$dotnet_resolved")" && pwd)"

project="$repo_root/packaging/dotnet/SSHFling.Tool/SSHFling.Tool.csproj"
build_root="$repo_root/build/dotnet"
dist_dir="$repo_root/dist"
home_dir="$build_root/home"
nuget_dir="$build_root/nuget-packages"
validation_dir="$build_root/validation"
package_path="$dist_dir/SSHFling.Tool.$version.nupkg"

export DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_NOLOGO=1
export DOTNET_ROOT="${DOTNET_ROOT:-$dotnet_root}"
export DOTNET_ROOT_X64="${DOTNET_ROOT_X64:-$DOTNET_ROOT}"
export DOTNET_CLI_HOME="$home_dir"
export NUGET_PACKAGES="$nuget_dir"
export NUGET_XMLDOC_MODE=skip

rm -rf "$build_root"
install -d "$home_dir" "$nuget_dir" "$validation_dir" "$dist_dir"
rm -f "$package_path"

"$dotnet_cmd" pack "$project" \
  --configuration Release \
  --output "$dist_dir" \
  -p:Version="$version" \
  -p:PackageVersion="$version" \
  -p:ContinuousIntegrationBuild=true

if [[ ! -s "$package_path" ]]; then
  echo "NuGet global tool package was not created: $package_path" >&2
  exit 1
fi

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
  test -x "$smoke_project/production/sshfling-session"
  test -f "$smoke_project/secrets/.gitkeep"
fi

printf '%s\n' "$package_path"
