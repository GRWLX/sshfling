#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

version="${SSHFLING_VERSION:-$(bash packaging/resolve-version.sh)}"
repository="${REPOSITORY:-GRWLX/sshfling}"
base_url="http://127.0.0.1:8000"
tmp="$(mktemp -d)"
containers=()
networks=()
last_container=""

cleanup() {
  local name
  for name in "${containers[@]}"; do
    docker rm -f "$name" >/dev/null 2>&1 || true
  done
  for name in "${networks[@]}"; do
    docker network rm "$name" >/dev/null 2>&1 || true
  done
  rm -rf "$tmp"
}
trap cleanup EXIT INT TERM

log() {
  printf '\n[container-tests] %s\n' "$*"
}

safe_name() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr '/:.' '---' | tr -cd 'a-z0-9_-'
}

start_container() {
  local image="$1"
  local safe_image
  local name
  shift
  safe_image="$(safe_name "$image")"
  name="sshfling-${safe_image}-$$-${#containers[@]}"
  docker rm -f "$name" >/dev/null 2>&1 || true
  docker run -d --name "$name" "$@" "$image" sh -lc 'sleep 3600' >/dev/null
  containers+=("$name")
  last_container="$name"
}

copy_validate() {
  local name="$1"
  docker cp tests/cross-os/validate-cli.sh "$name:/tmp/validate-cli.sh"
}

make_source_tar() {
  local output="$1"
  tar \
    --exclude=.git \
    --exclude=.github \
    --exclude=.codex \
    --exclude='.codex-*' \
    --exclude=build \
    --exclude=dist \
    --exclude=public \
    --exclude=package-dist \
    --exclude=release-dist \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    --exclude='secrets/client_ed25519' \
    --exclude='secrets/client_ed25519.pub' \
    --transform "s,^\.,sshfling-${version}," \
    -czf "$output" \
    .
}

prepare_artifacts() {
  log "building local package artifacts"
  SSHFLING_VERSION="$version" bash packaging/build-deb.sh >/dev/null
  SSHFLING_VERSION="$version" bash packaging/build-rpm.sh >/dev/null

  install -d "$tmp/site/downloads" "$tmp/package-dist"
  make_source_tar "$tmp/site/downloads/sshfling-${version}.tar.gz"
  bash packaging/build-community-manifests.sh \
    "$tmp/package-dist" \
    "$tmp/site" \
    "$base_url" \
    "$version" \
    "$repository"
}

pull_and_smoke_images() {
  local images=(
    debian:bookworm-slim
    ubuntu:24.04
    fedora:latest
    rockylinux:9
    almalinux:9
    registry.access.redhat.com/ubi9/ubi
    archlinux:latest
    alpine:3.20
    opensuse/tumbleweed
    nixos/nix:2.24.9
    vbatts/slackware:15.0
    ghcr.io/void-linux/void-glibc-full:latest
  )
  local image
  for image in "${images[@]}"; do
    log "pulling $image"
    docker pull "$image" >/dev/null
    docker run --rm "$image" sh -lc 'uname -s >/dev/null'
  done
}

test_compose_images() {
  log "building compose images"
  docker compose -f compose.server.yml -f compose.client.yml build --pull

  log "building and running production test image"
  docker build --pull -f tests/docker/Dockerfile.production -t sshfling-production-test:latest .
  docker run --rm sshfling-production-test:latest

  log "running server/client SSH round trip"
  local network="sshfling-test-net-$$"
  local key="$tmp/client_ed25519"
  local server="sshfling-compose-server-$$"
  networks+=("$network")
  containers+=("$server")

  ssh-keygen -q -t ed25519 -N "" -C "sshfling-container-test" -f "$key"
  docker network create "$network" >/dev/null
  docker run -d \
    --name "$server" \
    --network "$network" \
    --network-alias ssh-server \
    -e SSH_SESSION_SECONDS=20 \
    -e "SSH_AUTHORIZED_KEYS=$(cat "$key.pub")" \
    timed-ssh-server:latest >/dev/null

  for _ in $(seq 1 30); do
    if docker exec "$server" sh -lc 'test -s /home/deploy/.ssh/authorized_keys && pgrep -x sshd >/dev/null'; then
      break
    fi
    sleep 1
  done
  docker exec "$server" sh -lc 'test -s /home/deploy/.ssh/authorized_keys && pgrep -x sshd >/dev/null'

  local client_output
  client_output="$(docker run --rm \
    --network "$network" \
    -e "SSH_PRIVATE_KEY_B64=$(base64 -w0 "$key")" \
    -e SSH_COMMAND='whoami && hostname' \
    timed-ssh-client:latest)"
  printf '%s\n' "$client_output" | grep -Fq deploy
}

test_deb_image() {
  local image="$1"
  local name
  start_container "$image"
  name="$last_container"
  copy_validate "$name"
  docker cp "dist/sshfling_${version}_all.deb" "$name:/tmp/sshfling.deb"
  docker exec "$name" sh -lc "set -eu
    apt-get update >/dev/null
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends /tmp/sshfling.deb >/dev/null
    sh /tmp/validate-cli.sh sshfling '$version'"
}

test_rpm_image() {
  local image="$1"
  local name
  start_container "$image"
  name="$last_container"
  copy_validate "$name"
  docker cp "dist/sshfling-${version}-1.noarch.rpm" "$name:/tmp/sshfling.rpm"
  docker exec "$name" sh -lc "set -eu
    if command -v dnf >/dev/null 2>&1; then
      dnf install -y /tmp/sshfling.rpm >/dev/null
    else
      yum install -y /tmp/sshfling.rpm >/dev/null
    fi
    sh /tmp/validate-cli.sh sshfling '$version'"
}

test_opensuse() {
  local name
  start_container opensuse/tumbleweed
  name="$last_container"
  copy_validate "$name"
  docker cp "$tmp/site/downloads/sshfling-${version}.tar.gz" "$name:/tmp/sshfling-${version}.tar.gz"
  docker cp "$tmp/site/opensuse/sshfling.spec" "$name:/tmp/sshfling.spec"
  docker exec "$name" sh -lc "set -eu
    zypper --non-interactive --gpg-auto-import-keys refresh >/dev/null
    zypper --non-interactive --gpg-auto-import-keys install rpm-build tar gzip python3 openssh shadow procps util-linux >/dev/null
    mkdir -p /root/rpmbuild/SOURCES /root/rpmbuild/SPECS
    cp /tmp/sshfling-${version}.tar.gz /root/rpmbuild/SOURCES/
    cp /tmp/sshfling.spec /root/rpmbuild/SPECS/
    rpmbuild --define '_topdir /root/rpmbuild' -ba /root/rpmbuild/SPECS/sshfling.spec >/tmp/opensuse-rpmbuild.log
    rpm -Uvh /root/rpmbuild/RPMS/noarch/sshfling-${version}-1.noarch.rpm >/dev/null
    sh /tmp/validate-cli.sh sshfling '$version'"
}

test_arch() {
  local name
  start_container archlinux:latest
  name="$last_container"
  copy_validate "$name"
  docker exec "$name" sh -lc 'mkdir -p /srv/site /build'
  docker cp "$tmp/site/." "$name:/srv/site/"
  docker cp "$tmp/site/arch/PKGBUILD" "$name:/build/PKGBUILD"
  docker exec "$name" sh -lc "set -eu
    pacman -Sy --noconfirm --needed base-devel python openssh shadow procps-ng util-linux sudo >/dev/null
    python -m http.server 8000 --directory /srv/site >/tmp/http.log 2>&1 &
    http_pid=\$!
    trap 'kill \$http_pid 2>/dev/null || true' EXIT
    useradd -m builder
    echo 'builder ALL=(ALL) NOPASSWD: ALL' >/etc/sudoers.d/builder
    chown -R builder:builder /build
    cd /build
    sudo -u builder makepkg -si --noconfirm --needed >/tmp/arch-makepkg.log
    sh /tmp/validate-cli.sh sshfling '$version'"
}

test_alpine() {
  local name
  start_container alpine:3.20
  name="$last_container"
  copy_validate "$name"
  docker exec "$name" sh -lc 'mkdir -p /srv/site /build'
  docker cp "$tmp/site/." "$name:/srv/site/"
  docker cp "$tmp/site/alpine/APKBUILD" "$name:/build/APKBUILD"
  docker exec "$name" sh -lc "set -eu
    apk add --no-cache alpine-sdk curl python3 openssh-client shadow procps util-linux sudo >/dev/null
    python3 -m http.server 8000 --directory /srv/site >/tmp/http.log 2>&1 &
    http_pid=\$!
    trap 'kill \$http_pid 2>/dev/null || true' EXIT
    adduser -D builder
    addgroup builder abuild
    chown -R builder:builder /build
    su builder -c 'abuild-keygen -a -n' >/tmp/alpine-keygen.log
    cp /home/builder/.abuild/*.rsa.pub /etc/apk/keys/
    su builder -c 'cd /build && abuild checksum && abuild -r' >/tmp/alpine-build.log
    apk_file=\"\$(find /home/builder/packages -name 'sshfling-${version}-r0.apk' -print -quit)\"
    test -n \"\$apk_file\"
    apk add \"\$apk_file\" >/dev/null
    sh /tmp/validate-cli.sh sshfling '$version'"
}

test_slackware() {
  local name
  start_container vbatts/slackware:15.0
  name="$last_container"
  copy_validate "$name"
  docker exec "$name" /bin/sh -lc 'mkdir -p /tmp/slacktest'
  docker cp "$tmp/site/downloads/sshfling-${version}.tar.gz" "$name:/tmp/slacktest/sshfling-${version}.tar.gz"
  docker cp "$tmp/site/slackware/sshfling.SlackBuild" "$name:/tmp/slacktest/sshfling.SlackBuild"
  docker cp "$tmp/site/slackware/slack-desc" "$name:/tmp/slacktest/slack-desc"
  docker exec "$name" /bin/sh -lc "set -eu
    slackware_bootstrap_mirror=http://slackware.osuosl.org/slackware64-15.0
    slackware_https_mirror=https://slackware.osuosl.org/slackware64-15.0
    printf '%s\n' \"\${slackware_bootstrap_mirror}/\" >/etc/slackpkg/mirrors
    slackpkg -batch=on -default_answer=y update >/tmp/slackpkg-update.log 2>&1 || { cat /tmp/slackpkg-update.log; exit 1; }
    slackpkg -batch=on -default_answer=y install ca-certificates >/tmp/slackpkg-ca-certificates.log 2>&1 || { cat /tmp/slackpkg-ca-certificates.log; exit 1; }
    if command -v update-ca-certificates >/dev/null 2>&1; then update-ca-certificates >/tmp/update-ca-certificates.log 2>&1 || true; fi
    ssl_ca=/etc/ssl/certs/ca-certificates.crt
    test -s \"\$ssl_ca\"
    wget --ca-certificate=\"\$ssl_ca\" -qO /tmp/python3.txz \"\$slackware_https_mirror/slackware64/d/python3-3.9.10-x86_64-1.txz\"
    installpkg /tmp/python3.txz >/tmp/install-python3.log
    cd /tmp/slacktest
    chmod +x sshfling.SlackBuild
    ./sshfling.SlackBuild >/tmp/slackbuild.log
    installpkg /tmp/sshfling-${version}-noarch-1_SBo.txz >/tmp/installpkg.log
    sh /tmp/validate-cli.sh sshfling '$version'"
}

test_void() {
  local name
  start_container ghcr.io/void-linux/void-glibc-full:latest
  name="$last_container"
  copy_validate "$name"
  docker cp "$tmp/site/downloads/sshfling-${version}.tar.gz" "$name:/tmp/sshfling-${version}.tar.gz"
  docker exec "$name" sh -lc "set -eu
    xbps-install -Syu -y xbps >/dev/null || true
    xbps-install -Syu -y bash tar gzip python3 openssh shadow procps-ng util-linux coreutils >/dev/null
    cd /tmp
    tar -xzf sshfling-${version}.tar.gz
    cd sshfling-${version}
    install -Dm755 bin/sshfling /usr/bin/sshfling
    install -d /usr/share/sshfling/templates
    cp -a .env.example LICENSE README.md compose.server.yml compose.client.yml scripts secrets ssh-client ssh-server production systemd /usr/share/sshfling/templates/
    sh /tmp/validate-cli.sh sshfling '$version'"
}

test_nix() {
  local name
  local nix_env=()
  if [[ -n "${NIX_CONFIG:-}" ]]; then
    nix_env=(-e NIX_CONFIG)
  fi
  start_container nixos/nix:2.24.9 "${nix_env[@]}"
  name="$last_container"
  copy_validate "$name"
  docker cp "$tmp/site/downloads/sshfling-${version}.tar.gz" "$name:/tmp/sshfling-${version}.tar.gz"
  docker exec "$name" sh -lc "set -eu
    mkdir -p /work
    cd /work
    tar -xzf /tmp/sshfling-${version}.tar.gz
    cd sshfling-${version}
    NIXPKGS_ALLOW_UNFREE=1 nix --extra-experimental-features 'nix-command flakes' build --impure .#default -o result
    nix --extra-experimental-features 'nix-command flakes' shell nixpkgs#python3 -c sh /tmp/validate-cli.sh ./result/bin/sshfling '$version'"
}

prepare_artifacts
pull_and_smoke_images
test_compose_images

log "testing Debian and Ubuntu packages"
test_deb_image debian:bookworm-slim
test_deb_image ubuntu:24.04

log "testing RPM-family packages"
test_rpm_image fedora:latest
test_rpm_image rockylinux:9
test_rpm_image almalinux:9
test_rpm_image registry.access.redhat.com/ubi9/ubi

log "testing community package/container targets"
test_opensuse
test_arch
test_alpine
test_slackware
test_void
test_nix

log "all container image tests passed"
