#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=packaging/version.sh
source "$repo_root/packaging/version.sh"
version="$(assert_sshfling_version_matches_source "${SSHFLING_VERSION:-}" "$repo_root")"

python_cmd="${PYTHON:-python3}"
pipx_cmd="${PIPX:-pipx}"
if ! command -v "$python_cmd" >/dev/null 2>&1; then
  echo "Python 3.10 or newer is required to build the SSHFling wheel." >&2
  echo "Install Python, or set PYTHON to a Python executable." >&2
  exit 127
fi
if ! "$python_cmd" -c 'import sys; raise SystemExit(sys.version_info < (3, 10))'; then
  echo "Python 3.10 or newer is required to build the SSHFling wheel." >&2
  exit 2
fi
if ! "$python_cmd" -m pip --version >/dev/null 2>&1; then
  echo "pip is required to build and validate the SSHFling wheel." >&2
  exit 127
fi

dist_dir="$repo_root/dist"
build_root="$repo_root/build/python"
project_dir="$build_root/project"
validation_dir="$build_root/validation"
wheel_path="$dist_dir/sshfling-$version-py3-none-any.whl"

export LC_ALL=C
export TZ=UTC
export PIP_DISABLE_PIP_VERSION_CHECK=1
export PIP_NO_INPUT=1
umask 022

copy_python_project() {
  rm -rf "$project_dir"
  install -d "$project_dir/src/sshfling"
  install -m 0644 "$repo_root/packaging/python/pyproject.toml" "$project_dir/pyproject.toml"
  install -m 0644 "$repo_root/packaging/python/src/sshfling/__init__.py" "$project_dir/src/sshfling/__init__.py"
  install -m 0644 "$repo_root/bin/sshfling" "$project_dir/src/sshfling/cli.py"
  install -m 0644 "$repo_root/LICENSE" "$project_dir/LICENSE"
  install -m 0644 "$repo_root/README.md" "$project_dir/README.md"

  # shellcheck source=packaging/copy-templates.sh
  source "$repo_root/packaging/copy-templates.sh"
  copy_sshfling_templates "$repo_root" "$project_dir/src/sshfling/templates"
}

validate_wheel_contents() {
  local listing="$validation_dir/wheel-contents.txt"

  "$python_cmd" -m zipfile -l "$wheel_path" >"$listing"
  grep -Eq 'sshfling/cli\.py' "$listing"
  grep -Eq 'sshfling/templates/systemd/sshfling-prune\.service' "$listing"
  grep -Eq 'sshfling/templates/systemd/sshfling-prune\.timer' "$listing"
  grep -Eq 'sshfling/templates/native/sshfling-linux-account' "$listing"
  grep -Eq 'sshfling/templates/native/sshfling-unix-identity' "$listing"
  grep -Eq 'sshfling/templates/production/sshfling-login-shell' "$listing"
  grep -Eq 'sshfling/templates/\.env\.example' "$listing"
  grep -Eq 'sshfling/templates/secrets/\.gitkeep' "$listing"
  grep -Eq 'sshfling-.+\.dist-info/entry_points\.txt' "$listing"
  grep -Eq 'sshfling-.+\.dist-info/(licenses/)?LICENSE' "$listing"
}

validate_pip_install() {
  local venv_dir="$validation_dir/venv"
  local smoke_project="$validation_dir/pip-smoke-project"
  local bin_dir="bin"

  if [[ "$("$python_cmd" -c 'import os; print(os.name)')" == "nt" ]]; then
    bin_dir="Scripts"
  fi

  "$python_cmd" -m venv "$venv_dir"
  "$venv_dir/$bin_dir/python" -m pip install --no-deps --no-index "$wheel_path" >/dev/null
  "$venv_dir/$bin_dir/python" -c 'import sshfling; assert sshfling.__version__; assert sshfling.run(["--version"]) == 0'
  "$venv_dir/$bin_dir/sshfling" --version | grep -Fx "sshfling $version" >/dev/null
  "$venv_dir/$bin_dir/sshfling" --project-dir "$smoke_project" doctor >/dev/null
  "$venv_dir/$bin_dir/sshfling" init "$smoke_project" --force --session-seconds 60 >/dev/null
  test -x "$smoke_project/scripts/install-local.sh"
  test -x "$smoke_project/scripts/uninstall-local.sh"
  test -x "$smoke_project/native/sshfling-linux-account"
  test -x "$smoke_project/native/sshfling-unix-identity"
  test -x "$smoke_project/production/sshfling-login-shell"
  test -x "$smoke_project/production/sshfling-session"
  test -f "$smoke_project/secrets/.gitkeep"

  "$venv_dir/$bin_dir/python" -m pip uninstall --yes sshfling >/dev/null
  if "$venv_dir/$bin_dir/python" -c 'import sshfling' >/dev/null 2>&1; then
    echo "pip uninstall left the sshfling package importable." >&2
    exit 1
  fi
  test ! -e "$venv_dir/$bin_dir/sshfling"
}

validate_pipx_install() {
  local pipx_home="$validation_dir/pipx-home"
  local pipx_bin_dir="$validation_dir/pipx-bin"
  local smoke_project="$validation_dir/pipx-smoke-project"

  if ! command -v "$pipx_cmd" >/dev/null 2>&1; then
    if [[ "${SSHFLING_REQUIRE_PIPX:-}" == "1" ]]; then
      echo "pipx is required for this validation run." >&2
      exit 127
    fi
    echo "pipx not found; skipping optional local pipx validation." >&2
    return 0
  fi

  PIPX_HOME="$pipx_home" PIPX_BIN_DIR="$pipx_bin_dir" \
    "$pipx_cmd" install --pip-args='--no-deps --no-index' "$wheel_path" >/dev/null
  "$pipx_bin_dir/sshfling" --version | grep -Fx "sshfling $version" >/dev/null
  "$pipx_bin_dir/sshfling" init "$smoke_project" --force --session-seconds 60 >/dev/null
  test -x "$smoke_project/scripts/install-local.sh"
  test -x "$smoke_project/native/sshfling-linux-account"
  test -x "$smoke_project/native/sshfling-unix-identity"
  test -x "$smoke_project/production/sshfling-login-shell"
  test -f "$smoke_project/secrets/.gitkeep"
  PIPX_HOME="$pipx_home" PIPX_BIN_DIR="$pipx_bin_dir" \
    "$pipx_cmd" uninstall sshfling >/dev/null
  test ! -e "$pipx_bin_dir/sshfling"
}

rm -rf "$build_root"
install -d "$build_root" "$validation_dir" "$dist_dir"
rm -f "$wheel_path"

copy_python_project
(
  cd "$project_dir"
  "$python_cmd" -m pip wheel \
    --no-deps \
    --no-build-isolation \
    --wheel-dir "$dist_dir" \
    . >/dev/null
)

if [[ ! -s "$wheel_path" ]]; then
  echo "Python wheel was not created: $wheel_path" >&2
  exit 1
fi

validate_wheel_contents
validate_pip_install
validate_pipx_install

printf '%s\n' "$wheel_path"
