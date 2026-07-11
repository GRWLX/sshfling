#!/usr/bin/env bash
set -euo pipefail

base_url="${SSHFLING_BASE_URL:-https://grwlx.github.io/sshfling}"
expected_repo_fingerprint="AED68865441FEBF6408765BBCC12D29464D19EA9"
action="${1:-install}"
mode="${2:-auto}"

case "$action" in
  install|uninstall) ;;
  auto|apt)
    mode="$action"
    action="install"
    ;;
  *)
    echo "Usage: install.sh [install|uninstall] [auto|apt]" >&2
    echo "       install.sh [auto|apt]" >&2
    exit 2
    ;;
esac

normalize_fingerprint() {
  printf '%s' "${1:-}" | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]'
}

fingerprint_key_file() {
  local key_file="$1"
  if ! command -v gpg >/dev/null 2>&1; then
    echo "gpg is required to verify the SSHFling repository signing key fingerprint." >&2
    return 127
  fi
  gpg --batch --show-keys --with-colons "$key_file" | awk -F: '/^fpr:/ {print toupper($10); exit}'
}

install_apt() {
  local tmp expected actual
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  expected="$(normalize_fingerprint "$expected_repo_fingerprint")"
  curl -fsSL "${base_url}/sshfling-repo.gpg" -o "$tmp/sshfling-repo.gpg"
  curl -fsSL "${base_url}/apt/InRelease" -o "$tmp/InRelease"
  actual="$(fingerprint_key_file "$tmp/sshfling-repo.gpg")"
  if [[ -z "$actual" || "$actual" != "$expected" ]]; then
    echo "Repository signing key fingerprint mismatch." >&2
    echo "Expected: $expected" >&2
    echo "Actual:   ${actual:-UNKNOWN}" >&2
    return 2
  fi
  sudo rm -f /etc/apt/sources.list.d/fling.list /etc/apt/preferences.d/fling /etc/apt/preferences.d/sshfling
  sudo install -d -m 0755 /usr/share/keyrings
  sudo install -m 0644 "$tmp/sshfling-repo.gpg" /usr/share/keyrings/sshfling-repo.gpg
  printf 'deb [signed-by=/usr/share/keyrings/sshfling-repo.gpg] %s/apt ./\n' "$base_url" >"$tmp/sshfling.list"
  sudo install -m 0644 "$tmp/sshfling.list" /etc/apt/sources.list.d/sshfling.list
  sudo apt-get update
  sudo apt-get install -y sshfling
}

uninstall_apt() {
  if dpkg -s sshfling >/dev/null 2>&1; then
    sudo apt-get remove -y sshfling
  fi
  sudo rm -f \
    /etc/apt/sources.list.d/sshfling.list \
    /etc/apt/sources.list.d/fling.list \
    /etc/apt/preferences.d/sshfling \
    /etc/apt/preferences.d/fling \
    /usr/share/keyrings/sshfling-repo.gpg
  sudo apt-get update || true
}

case "$mode" in
  auto|apt) "${action}_apt" ;;
  *)
    echo "Usage: install.sh [install|uninstall] [auto|apt]" >&2
    echo "       install.sh [auto|apt]" >&2
    exit 2
    ;;
esac
