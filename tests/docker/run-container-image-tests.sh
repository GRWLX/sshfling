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
  log "testing DEB package lifecycle on $image"
  start_container "$image"
  name="$last_container"
  copy_validate "$name"
  docker cp "dist/sshfling_${version}_all.deb" "$name:/tmp/sshfling.deb"
  docker exec "$name" sh -lc "set -eu
    assert_sshflingd_account_present() {
      getent passwd sshflingd >/dev/null
      getent group sshflingd >/dev/null
      test \"\$(getent passwd sshflingd | cut -d: -f6)\" = '/var/lib/sshflingd'
      case \"\$(getent passwd sshflingd | cut -d: -f7)\" in
        */nologin) ;;
        *) echo 'sshflingd account does not use nologin shell' >&2; exit 1 ;;
      esac
    }
    assert_sshflingd_account_absent() {
      if getent passwd sshflingd >/dev/null; then
        echo 'package-created sshflingd user survived cleanup' >&2
        exit 1
      fi
      if getent group sshflingd >/dev/null; then
        echo 'package-created sshflingd group survived cleanup' >&2
        exit 1
      fi
    }
    create_preexisting_sshflingd_account() {
      nologin=/usr/sbin/nologin
      if [ ! -x \"\$nologin\" ] && [ -x /sbin/nologin ]; then
        nologin=/sbin/nologin
      fi
      groupadd --system sshflingd 2>/dev/null || groupadd -r sshflingd
      useradd --system --gid sshflingd --home-dir /var/lib/sshflingd --shell \"\$nologin\" --no-create-home sshflingd 2>/dev/null \
        || useradd -r -g sshflingd -d /var/lib/sshflingd -s \"\$nologin\" -M sshflingd
      install -d -m 0750 -o sshflingd -g sshflingd /var/lib/sshflingd
      touch /var/lib/sshflingd/preexisting
      chown sshflingd:sshflingd /var/lib/sshflingd/preexisting
    }
    apt-get update >/dev/null
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends -o Dpkg::Options::=--force-confold /tmp/sshfling.deb >/dev/null
    sshfling --version | grep -Fx 'sshfling $version'
    assert_sshflingd_account_present
    test -d /var/lib/sshflingd
    test -f /var/lib/sshfling/package-state/install-state
    test ! -e /var/lib/sshflingd/package-state/install-state
    test \"\$(stat -c '%u:%g' /var/lib/sshfling/package-state)\" = '0:0'
    test \"\$(stat -c '%a' /var/lib/sshfling/package-state)\" = '700'
    printf '%s\n' '{\"version\":2,\"default\":{\"max_time_seconds\":123,\"max_connections\":1,\"access_level\":\"standard\"}}' >/etc/sshfling/policy.json
    DEBIAN_FRONTEND=noninteractive apt-get remove -y sshfling >/dev/null
    if [ -e /usr/bin/sshfling ]; then
      echo 'sshfling command survived deb package removal' >&2
      exit 1
    fi
    assert_sshflingd_account_present
    grep -Fq '\"max_time_seconds\":123' /etc/sshfling/policy.json
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends -o Dpkg::Options::=--force-confold /tmp/sshfling.deb >/dev/null
    grep -Fq '\"max_time_seconds\":123' /etc/sshfling/policy.json
    sh /tmp/validate-cli.sh sshfling '$version'
    DEBIAN_FRONTEND=noninteractive apt-get purge -y sshfling >/dev/null
    test ! -e /var/lib/sshfling/package-state/install-state
    test ! -e /var/lib/sshflingd/package-state/install-state
	    test ! -e /var/lib/sshflingd
	    assert_sshflingd_account_absent

	    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends -o Dpkg::Options::=--force-confold /tmp/sshfling.deb >/dev/null
	    test -f /var/lib/sshfling/package-state/install-state
	    grep -Eq '^user_uid=[0-9]+' /var/lib/sshfling/package-state/install-state
	    grep -Eq '^user_gid=[0-9]+' /var/lib/sshfling/package-state/install-state
	    grep -Fqx 'user_home=/var/lib/sshflingd' /var/lib/sshfling/package-state/install-state
	    sed -i 's/^user_uid=.*/user_uid=1/; s/^user_gid=.*/user_gid=1/; s#^user_home=.*#user_home=/var/lib/sshflingd-reused#' /var/lib/sshfling/package-state/install-state
	    DEBIAN_FRONTEND=noninteractive apt-get purge -y sshfling >/dev/null
	    assert_sshflingd_account_present
	    test -d /var/lib/sshflingd
	    userdel sshflingd >/dev/null 2>&1 || true
	    groupdel sshflingd >/dev/null 2>&1 || true
	    rm -rf /var/lib/sshflingd
	    assert_sshflingd_account_absent

	    create_preexisting_sshflingd_account
	    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends -o Dpkg::Options::=--force-confold /tmp/sshfling.deb >/dev/null
	    grep -Fqx 'user_preexisting=yes' /var/lib/sshfling/package-state/install-state
	    grep -Fqx 'group_preexisting=yes' /var/lib/sshfling/package-state/install-state
	    grep -Fqx 'var_dir_preexisting=yes' /var/lib/sshfling/package-state/install-state
    assert_sshflingd_account_present
    DEBIAN_FRONTEND=noninteractive apt-get purge -y sshfling >/dev/null
    test ! -e /var/lib/sshfling/package-state/install-state
    test -e /var/lib/sshflingd/preexisting
    assert_sshflingd_account_present"
}

test_rpm_image() {
  local image="$1"
  local name
  log "testing RPM package lifecycle on $image"
  start_container "$image"
  name="$last_container"
  copy_validate "$name"
  docker cp "dist/sshfling-${version}-1.noarch.rpm" "$name:/tmp/sshfling.rpm"
  docker exec "$name" sh -lc "set -eu
    assert_sshflingd_account_present() {
      getent passwd sshflingd >/dev/null
      getent group sshflingd >/dev/null
      test \"\$(getent passwd sshflingd | cut -d: -f6)\" = '/var/lib/sshflingd'
      case \"\$(getent passwd sshflingd | cut -d: -f7)\" in
        */nologin) ;;
        *) echo 'sshflingd account does not use nologin shell' >&2; exit 1 ;;
      esac
    }
    assert_sshflingd_account_absent() {
      if getent passwd sshflingd >/dev/null; then
        echo 'package-created sshflingd user survived cleanup' >&2
        exit 1
      fi
      if getent group sshflingd >/dev/null; then
        echo 'package-created sshflingd group survived cleanup' >&2
        exit 1
      fi
    }
    create_preexisting_sshflingd_account() {
      nologin=/usr/sbin/nologin
      if [ ! -x \"\$nologin\" ] && [ -x /sbin/nologin ]; then
        nologin=/sbin/nologin
      fi
      groupadd --system sshflingd 2>/dev/null || groupadd -r sshflingd
      useradd --system --gid sshflingd --home-dir /var/lib/sshflingd --shell \"\$nologin\" --no-create-home sshflingd 2>/dev/null \
        || useradd -r -g sshflingd -d /var/lib/sshflingd -s \"\$nologin\" -M sshflingd
      install -d -m 0750 -o sshflingd -g sshflingd /var/lib/sshflingd
      touch /var/lib/sshflingd/preexisting
      chown sshflingd:sshflingd /var/lib/sshflingd/preexisting
    }
    if command -v dnf >/dev/null 2>&1; then
      package_install='dnf install -y /tmp/sshfling.rpm'
    else
      package_install='yum install -y /tmp/sshfling.rpm'
    fi
    \$package_install >/dev/null
    sshfling --version | grep -Fx 'sshfling $version'
    assert_sshflingd_account_present
    test -d /var/lib/sshflingd
    test -f /var/lib/sshfling/package-state/install-state
    test ! -e /var/lib/sshflingd/package-state/install-state
    test \"\$(stat -c '%u:%g' /var/lib/sshfling/package-state)\" = '0:0'
    test \"\$(stat -c '%a' /var/lib/sshfling/package-state)\" = '700'
    printf '%s\n' '{\"version\":2,\"default\":{\"max_time_seconds\":123,\"max_connections\":1,\"access_level\":\"standard\"}}' >/etc/sshfling/policy.json
    rpm -e sshfling >/dev/null
    if [ -e /usr/bin/sshfling ]; then
      echo 'sshfling command survived rpm package removal' >&2
      exit 1
    fi
    test -f /var/lib/sshfling/package-state/install-state
    test ! -e /var/lib/sshfling/rpm-preserve-config
    assert_sshflingd_account_present
    grep -Fq '\"max_time_seconds\":123' /etc/sshfling/policy.json
    \$package_install >/dev/null
    grep -Fq '\"max_time_seconds\":123' /etc/sshfling/policy.json
    sh /tmp/validate-cli.sh sshfling '$version'

    rm -f /etc/sshfling/policy.json /etc/sshfling/policy.json.rpmnew /etc/sshfling/policy.json.rpmsave /etc/sshfling/sshflingd.env /etc/sshfling/sshflingd.env.rpmnew /etc/sshfling/sshflingd.env.rpmsave
    rpm -e sshfling >/dev/null
    test ! -e /var/lib/sshfling/package-state/install-state
    test ! -e /var/lib/sshfling/rpm-preserve-config
	    test ! -e /var/lib/sshflingd
	    test ! -e /etc/sshfling
	    assert_sshflingd_account_absent

	    \$package_install >/dev/null
	    test -f /var/lib/sshfling/package-state/install-state
	    grep -Eq '^user_uid=[0-9]+' /var/lib/sshfling/package-state/install-state
	    grep -Eq '^user_gid=[0-9]+' /var/lib/sshfling/package-state/install-state
	    grep -Fqx 'user_home=/var/lib/sshflingd' /var/lib/sshfling/package-state/install-state
	    sed -i 's/^user_uid=.*/user_uid=1/; s/^user_gid=.*/user_gid=1/; s#^user_home=.*#user_home=/var/lib/sshflingd-reused#' /var/lib/sshfling/package-state/install-state
	    rm -f /etc/sshfling/policy.json /etc/sshfling/policy.json.rpmnew /etc/sshfling/policy.json.rpmsave /etc/sshfling/sshflingd.env /etc/sshfling/sshflingd.env.rpmnew /etc/sshfling/sshflingd.env.rpmsave
	    rpm -e sshfling >/dev/null
	    assert_sshflingd_account_present
	    test -d /var/lib/sshflingd
	    userdel sshflingd >/dev/null 2>&1 || true
	    groupdel sshflingd >/dev/null 2>&1 || true
	    rm -rf /var/lib/sshflingd
	    assert_sshflingd_account_absent

		    create_preexisting_sshflingd_account
		    \$package_install >/dev/null
		    grep -Fqx 'user_preexisting=yes' /var/lib/sshfling/package-state/install-state
		    grep -Fqx 'group_preexisting=yes' /var/lib/sshfling/package-state/install-state
		    grep -Fqx 'var_dir_preexisting=yes' /var/lib/sshfling/package-state/install-state
    assert_sshflingd_account_present
    rm -f /etc/sshfling/policy.json /etc/sshfling/policy.json.rpmnew /etc/sshfling/policy.json.rpmsave /etc/sshfling/sshflingd.env /etc/sshfling/sshflingd.env.rpmnew /etc/sshfling/sshflingd.env.rpmsave
    rpm -e sshfling >/dev/null
    test ! -e /var/lib/sshfling/package-state/install-state
    test ! -e /var/lib/sshfling/rpm-preserve-config
    test -e /var/lib/sshflingd/preexisting
    assert_sshflingd_account_present"
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
    slackpkg -batch=on -default_answer=y install openssh >/tmp/slackpkg-openssh.log 2>&1 || { cat /tmp/slackpkg-openssh.log; exit 1; }
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
    nix --extra-experimental-features 'nix-command flakes' shell nixpkgs#coreutils nixpkgs#gnugrep nixpkgs#gnused nixpkgs#openssh nixpkgs#python3 -c sh /tmp/validate-cli.sh ./result/bin/sshfling '$version'"
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
