#!/usr/bin/env bash
set -euo pipefail

install_dir="${RELEASE_SCANNER_BIN_DIR:-${RUNNER_TEMP:-$PWD/build}/release-scanners/bin}"
mkdir -p "$install_dir"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "$1 is required to provision release scanners." >&2
    exit 127
  fi
}

need python3

if ! python3 -m pip --version >/dev/null 2>&1; then
  if command -v sudo >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y --no-install-recommends python3-pip
  fi
fi
python3 -m pip --version >/dev/null 2>&1 || {
  echo "python3 pip is required to install pinned Bandit." >&2
  exit 127
}

venv_dir="${RELEASE_SCANNER_VENV_DIR:-$(dirname "$install_dir")/venv}"

python_externally_managed() {
  python3 - <<'PY'
import os
import sysconfig

marker = os.path.join(sysconfig.get_path("stdlib"), "EXTERNALLY-MANAGED")
raise SystemExit(0 if os.path.exists(marker) else 1)
PY
}

install_bandit_venv() {
  if ! python3 -m venv "$venv_dir" >/dev/null 2>&1; then
    if command -v sudo >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1; then
      sudo apt-get update
      sudo apt-get install -y --no-install-recommends python3-venv
    fi
    python3 -m venv "$venv_dir"
  fi
  "$venv_dir/bin/python" -m pip install --upgrade pip
  "$venv_dir/bin/python" -m pip install "bandit==1.7.10"
  ln -sf "$venv_dir/bin/bandit" "$install_dir/bandit"
}

if python_externally_managed; then
  install_bandit_venv
elif python3 -m pip install --user --upgrade "bandit==1.7.10"; then
  user_base="$(python3 -m site --user-base)"
  if [ -x "$user_base/bin/bandit" ]; then
    ln -sf "$user_base/bin/bandit" "$install_dir/bandit"
  else
    cat >"$install_dir/bandit" <<'SH'
#!/usr/bin/env bash
exec python3 -m bandit "$@"
SH
    chmod 0755 "$install_dir/bandit"
  fi
else
  install_bandit_venv
fi

download_file() {
  url="$1"
  destination="$2"
  command -v curl >/dev/null 2>&1 || return 1
  curl -fsSL --retry 3 --proto '=https' --tlsv1.2 -o "$destination" "$url"
}

install_tar_binary() {
  archive="$1"
  binary_name="$2"
  destination="$3"
  extract_dir="$tmp_dir/extract-$binary_name"
  rm -rf "$extract_dir"
  mkdir -p "$extract_dir"
  tar -xzf "$archive" -C "$extract_dir"
  binary_path="$(find "$extract_dir" -type f -name "$binary_name" -print -quit)"
  [ -n "$binary_path" ] || return 1
  cp "$binary_path" "$destination"
  chmod 0755 "$destination"
}

native_os_arch() {
  case "$(uname -s)" in
    Linux) native_os="linux" ;;
    Darwin) native_os="darwin" ;;
    *) return 1 ;;
  esac

  case "$(uname -m)" in
    x86_64|amd64) native_arch="amd64"; native_arch_alt="x86_64"; native_arch_x64="x64" ;;
    aarch64|arm64) native_arch="arm64"; native_arch_alt="arm64"; native_arch_x64="arm64" ;;
    *) return 1 ;;
  esac
}

install_hadolint_native() {
  native_os_arch || return 1
  [ "$native_os" = "linux" ] || return 1
  download_file "https://github.com/hadolint/hadolint/releases/download/v2.12.0/hadolint-Linux-$native_arch_alt" "$install_dir/hadolint"
  chmod 0755 "$install_dir/hadolint"
  "$install_dir/hadolint" --version >/dev/null
}

install_syft_native() {
  native_os_arch || return 1
  archive="$tmp_dir/syft.tar.gz"
  download_file "https://github.com/anchore/syft/releases/download/v1.18.1/syft_1.18.1_${native_os}_${native_arch}.tar.gz" "$archive"
  install_tar_binary "$archive" syft "$install_dir/syft"
  "$install_dir/syft" version >/dev/null
}

install_gitleaks_native() {
  native_os_arch || return 1
  [ "$native_os" = "linux" ] || return 1
  archive="$tmp_dir/gitleaks.tar.gz"
  download_file "https://github.com/gitleaks/gitleaks/releases/download/v8.21.2/gitleaks_8.21.2_linux_${native_arch_x64}.tar.gz" "$archive"
  install_tar_binary "$archive" gitleaks "$install_dir/gitleaks"
  "$install_dir/gitleaks" version >/dev/null
}

install_trivy_native() {
  return 1
}

install_osv_scanner_native() {
  native_os_arch || return 1
  [ "$native_os" = "linux" ] || return 1
  download_file "https://github.com/google/osv-scanner/releases/download/v1.9.2/osv-scanner_linux_${native_arch}" "$install_dir/osv-scanner"
  chmod 0755 "$install_dir/osv-scanner"
  "$install_dir/osv-scanner" --version >/dev/null
}

write_docker_wrapper() {
  name="$1"
  image="$2"
  command_name="${3:-}"
  docker pull "$image" >/dev/null
  cat >"$install_dir/$name" <<SH
#!/usr/bin/env bash
set -euo pipefail
host_pwd="\${PWD%/}"
args=()
for arg in "\$@"; do
  case "\$arg" in
    "\$host_pwd")
      args+=("/work")
      ;;
    "\$host_pwd"/*)
      args+=("/work/\${arg#"\$host_pwd"/}")
      ;;
    *)
      args+=("\$arg")
      ;;
  esac
done
container=""
cleanup() {
  if [ -n "\$container" ]; then
    docker rm -f "\$container" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT
if [ -n "$command_name" ]; then
  container="\$(docker create -w /work "$image" "$command_name" "\${args[@]}")"
else
  container="\$(docker create -w /work "$image" "\${args[@]}")"
fi
docker cp "\$host_pwd/." "\$container:/work" >/dev/null
set +e
docker start -a "\$container"
status="\$?"
set -e
for arg in "\${args[@]}"; do
  case "\$arg" in
    /work/*)
      rel="\${arg#/work/}"
      ;;
    build/*|dist/*|public/*|package-dist/*|release-dist/*)
      rel="\$arg"
      ;;
    *)
      continue
      ;;
  esac
  case "\$rel" in
    *.json|*.spdx|*.spdx.json|*.sarif|*.txt|*.log)
      mkdir -p "\$host_pwd/\$(dirname "\$rel")"
      docker cp "\$container:/work/\$rel" "\$host_pwd/\$rel" >/dev/null 2>&1 || true
      ;;
  esac
done
exit "\$status"
SH
  chmod 0755 "$install_dir/$name"
}

provision_native_or_docker() {
  name="$1"
  image="$2"
  command_name="$3"
  native_installer="$4"

  if "$native_installer"; then
    return 0
  fi

  need docker
  write_docker_wrapper "$name" "$image" "$command_name"
}

provision_native_or_docker hadolint "hadolint/hadolint:v2.12.0" "hadolint" install_hadolint_native
provision_native_or_docker syft "anchore/syft:v1.18.1" "" install_syft_native
provision_native_or_docker gitleaks "zricethezav/gitleaks:v8.21.2" "" install_gitleaks_native
provision_native_or_docker trivy "aquasec/trivy:0.57.1" "" install_trivy_native
provision_native_or_docker osv-scanner "ghcr.io/google/osv-scanner:v1.9.2" "" install_osv_scanner_native

if [ -n "${GITHUB_PATH:-}" ]; then
  printf '%s\n' "$install_dir" >>"$GITHUB_PATH"
else
  export PATH="$install_dir:$PATH"
fi

for tool in bandit hadolint syft gitleaks trivy osv-scanner; do
  if [ -n "${GITHUB_PATH:-}" ]; then
    test -x "$install_dir/$tool"
  else
    command -v "$tool" >/dev/null 2>&1
  fi
done

echo "Provisioned release scanners in $install_dir"
