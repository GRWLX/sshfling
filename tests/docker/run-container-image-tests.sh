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
  docker cp tests/cross-os/validate-native-login-shell.sh "$name:/tmp/validate-native-login-shell.sh"
  docker cp tests/cross-os/validate-native-session-policy.sh "$name:/tmp/validate-native-session-policy.sh"
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
    --exclude=docs/release/evidence-manifest.json \
    --exclude=docs/release/enterprise-release-readiness-checklist.md \
    --exclude=docs/release/enterprise-release-matrix.csv \
    --exclude=docs/release/enterprise-release-summary.md \
    --exclude=docs/release/enterprise-release-evidence \
    --exclude='packaging/dotnet/**/bin' \
    --exclude='packaging/dotnet/**/obj' \
    --exclude='packaging/java/**/target' \
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

build_compose_images() {
  log "building compose images"
  if docker buildx version >/dev/null 2>&1; then
    docker compose -f compose.server.yml -f compose.client.yml build --pull
  else
    COMPOSE_BAKE=false DOCKER_BUILDKIT=0 \
      docker compose -f compose.server.yml -f compose.client.yml build --pull
  fi
  docker image inspect timed-ssh-server:latest timed-ssh-client:latest >/dev/null
}

test_production_image() {
  log "building and running production test image"
  docker build --pull -f tests/docker/Dockerfile.production -t sshfling-production-test:latest .
  docker run --rm sshfling-production-test:latest
}

test_compose_round_trip() {
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

test_compose_images() {
  build_compose_images
  test_production_image
  test_compose_round_trip
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
    assert_deb_dependencies_present() {
      for pkg in bash python3 openssh-client openssl passwd procps util-linux jq; do
        dpkg-query -W -f='\${Status}' \"\$pkg\" | grep -Fx 'install ok installed' >/dev/null
      done
    }
    test ! -d /run/systemd/system
    apt-get update >/dev/null
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends -o Dpkg::Options::=--force-confold /tmp/sshfling.deb >/dev/null
    assert_deb_dependencies_present
    test -x /usr/libexec/sshfling/sshfling-linux-account
    test -x /usr/libexec/sshfling/sshfling-unix-identity
    /usr/libexec/sshfling/sshfling-linux-account identity root | grep -Fq 'status=present'
    /usr/libexec/sshfling/sshfling-unix-identity identity root | grep -Fq 'uid=0'
    /usr/libexec/sshfling/sshfling-linux-account create sshflingtest /bin/sh | grep -Fq 'created=true'
    printf '%s\n' 'native-test-password' \
      | /usr/libexec/sshfling/sshfling-linux-account set-password sshflingtest \
      | grep -Fq 'password_set=true'
    /usr/libexec/sshfling/sshfling-linux-account lock sshflingtest | grep -Fq 'locked=true'
    /usr/libexec/sshfling/sshfling-linux-account delete sshflingtest | grep -Fq 'deleted=true'
    ! id -u sshflingtest >/dev/null 2>&1
    test -x /usr/share/sshfling/templates/production/sshfling-login-shell
    bash /tmp/validate-native-session-policy.sh /usr/share/sshfling/templates/production/sshfling-session >/dev/null
    sshfling --version | grep -Fx 'sshfling $version'
    assert_sshflingd_account_present
    test -d /var/lib/sshflingd
    test -f /var/lib/sshfling/package-state/install-state
    test ! -e /var/lib/sshflingd/package-state/install-state
    test \"\$(stat -c '%u:%g' /var/lib/sshfling/package-state)\" = '0:0'
    test \"\$(stat -c '%a' /var/lib/sshfling/package-state)\" = '700'
    printf '%s\n' '{\"version\":2,\"default\":{\"max_time_seconds\":123,\"max_connections\":1,\"access_level\":\"standard\"}}' >/etc/sshfling/policy.json
    DEBIAN_FRONTEND=noninteractive apt-get remove -y sshfling >/dev/null
    assert_deb_dependencies_present
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
    assert_deb_dependencies_present
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
	    assert_deb_dependencies_present
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
    assert_deb_dependencies_present
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
    assert_rpm_dependencies_present() {
      rpm -q bash python3 openssh-clients openssl shadow-utils procps-ng util-linux jq >/dev/null
    }
    test ! -d /run/systemd/system
    if command -v dnf >/dev/null 2>&1; then
      package_install='dnf install -y /tmp/sshfling.rpm'
    else
      package_install='yum install -y /tmp/sshfling.rpm'
    fi
    \$package_install >/dev/null
    assert_rpm_dependencies_present
    test -x /usr/libexec/sshfling/sshfling-linux-account
    test -x /usr/libexec/sshfling/sshfling-unix-identity
    /usr/libexec/sshfling/sshfling-linux-account identity root | grep -Fq 'status=present'
    /usr/libexec/sshfling/sshfling-unix-identity identity root | grep -Fq 'uid=0'
    /usr/libexec/sshfling/sshfling-linux-account create sshflingtest /bin/sh | grep -Fq 'created=true'
    printf '%s\n' 'native-test-password' \
      | /usr/libexec/sshfling/sshfling-linux-account set-password sshflingtest \
      | grep -Fq 'password_set=true'
    /usr/libexec/sshfling/sshfling-linux-account lock sshflingtest | grep -Fq 'locked=true'
    /usr/libexec/sshfling/sshfling-linux-account delete sshflingtest | grep -Fq 'deleted=true'
    ! id -u sshflingtest >/dev/null 2>&1
    test -x /usr/share/sshfling/templates/production/sshfling-login-shell
    bash /tmp/validate-native-session-policy.sh /usr/share/sshfling/templates/production/sshfling-session >/dev/null
    sshfling --version | grep -Fx 'sshfling $version'
    assert_sshflingd_account_present
    test -d /var/lib/sshflingd
    test -f /var/lib/sshfling/package-state/install-state
    test ! -e /var/lib/sshflingd/package-state/install-state
    test \"\$(stat -c '%u:%g' /var/lib/sshfling/package-state)\" = '0:0'
    test \"\$(stat -c '%a' /var/lib/sshfling/package-state)\" = '700'
    printf '%s\n' '{\"version\":2,\"default\":{\"max_time_seconds\":123,\"max_connections\":1,\"access_level\":\"standard\"}}' >/etc/sshfling/policy.json
    rpm -e sshfling >/dev/null
    assert_rpm_dependencies_present
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
    assert_rpm_dependencies_present
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
	    assert_rpm_dependencies_present
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
    assert_rpm_dependencies_present
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
    zypper --non-interactive --gpg-auto-import-keys install rpm-build tar gzip python3 jq openssh shadow procps util-linux >/dev/null
    mkdir -p /root/rpmbuild/SOURCES /root/rpmbuild/SPECS
    cp /tmp/sshfling-${version}.tar.gz /root/rpmbuild/SOURCES/
    cp /tmp/sshfling.spec /root/rpmbuild/SPECS/
    rpmbuild --define '_topdir /root/rpmbuild' -ba /root/rpmbuild/SPECS/sshfling.spec >/tmp/opensuse-rpmbuild.log
    rpm -Uvh /root/rpmbuild/RPMS/noarch/sshfling-${version}-1.noarch.rpm >/dev/null
    test -x /usr/libexec/sshfling/sshfling-linux-account
    test -x /usr/libexec/sshfling/sshfling-unix-identity
    /usr/libexec/sshfling/sshfling-linux-account identity root | grep -Fq 'status=present'
    /usr/libexec/sshfling/sshfling-unix-identity identity root | grep -Fq 'uid=0'
    /usr/libexec/sshfling/sshfling-linux-account create sshflingtest /bin/sh | grep -Fq 'created=true'
    printf '%s\n' 'native-test-password' \
      | /usr/libexec/sshfling/sshfling-linux-account set-password sshflingtest \
      | grep -Fq 'password_set=true'
    /usr/libexec/sshfling/sshfling-linux-account lock sshflingtest | grep -Fq 'locked=true'
    /usr/libexec/sshfling/sshfling-linux-account delete sshflingtest | grep -Fq 'deleted=true'
    ! id -u sshflingtest >/dev/null 2>&1
    test -x /usr/share/sshfling/templates/production/sshfling-login-shell
    bash /tmp/validate-native-session-policy.sh /usr/share/sshfling/templates/production/sshfling-session >/dev/null
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
    pacman -Sy --noconfirm --needed base-devel busybox python openssh shadow procps-ng util-linux sudo >/dev/null
    busybox httpd -f -p 8000 -h /srv/site >/tmp/http.log 2>&1 &
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
    apk add --no-cache alpine-sdk bash busybox-extras curl jq python3 openssh-client shadow procps util-linux sudo >/dev/null
    httpd -f -p 8000 -h /srv/site >/tmp/http.log 2>&1 &
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
    wget --ca-certificate=\"\$ssl_ca\" -qO /tmp/jq https://github.com/jqlang/jq/releases/download/jq-1.8.1/jq-linux-amd64
    printf '%s  %s\n' 020468de7539ce70ef1bceaf7cde2e8c4f2ca6c3afb84642aabc5c97d9fc2a0d /tmp/jq | sha256sum -c -
    install -m 0755 /tmp/jq /usr/local/bin/jq
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
    xbps-install -Syu -y bash tar gzip python3 jq openssh shadow procps-ng util-linux coreutils >/dev/null
    cd /tmp
    tar -xzf sshfling-${version}.tar.gz
    cd sshfling-${version}
    install -Dm755 bin/sshfling /usr/bin/sshfling
    install -Dm755 native/sshfling-linux-account /usr/libexec/sshfling/sshfling-linux-account
    install -Dm755 native/sshfling-unix-identity /usr/libexec/sshfling/sshfling-unix-identity
    install -d /usr/share/sshfling/templates
    cp -a .env.example LICENSE README.md compose.server.yml compose.client.yml native scripts secrets ssh-client ssh-server production systemd /usr/share/sshfling/templates/
    /usr/libexec/sshfling/sshfling-linux-account identity root | grep -Fq 'status=present'
    /usr/libexec/sshfling/sshfling-unix-identity identity root | grep -Fq 'uid=0'
    bash /tmp/validate-native-session-policy.sh /usr/share/sshfling/templates/production/sshfling-session >/dev/null
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
    closure_file=/tmp/sshfling-nix-closure
    nix-store -qR ./result >\"\$closure_file\"
    find_closure_tool() {
      tool=\$1
      while IFS= read -r store_path; do
        if [ -x \"\$store_path/bin/\$tool\" ]; then
          printf '%s\n' \"\$store_path/bin/\$tool\"
          return 0
        fi
      done <\"\$closure_file\"
      printf 'missing %s in the sshfling package closure\n' \"\$tool\" >&2
      return 1
    }
    IFS= read -r session_shebang <./result/share/sshfling/templates/production/sshfling-session
    harness_bash=\${session_shebang#\#!}
    case \"\$harness_bash\" in
      /nix/store/*/bin/bash) test -x \"\$harness_bash\" ;;
      *) printf 'invalid packaged session shebang: %s\n' \"\$session_shebang\" >&2; exit 1 ;;
    esac
    coreutils_tool=\"\$(find_closure_tool mktemp)\"
    grep_tool=\"\$(command -v grep)\"
    case \"\$grep_tool\" in
      /*) test -x \"\$grep_tool\" ;;
      *) printf 'invalid harness grep path: %s\n' \"\$grep_tool\" >&2; exit 1 ;;
    esac
    sed_tool=\"\$(find_closure_tool sed)\"
    python_tool=\"\$(find_closure_tool python3)\"
    ssh_tool=\"\$(find_closure_tool ssh)\"
    harness_path=\"\${harness_bash%/*}:\${coreutils_tool%/*}:\${grep_tool%/*}:\${sed_tool%/*}:\${python_tool%/*}:\${ssh_tool%/*}\"
    minimal_path=/tmp/sshfling-empty-path
    mkdir -p \"\$minimal_path\"
    account_output=\"\$(PATH=\"\$minimal_path\" ./result/libexec/sshfling/sshfling-linux-account identity root)\"
    case \"\$account_output\" in *status=present*) ;; *) exit 1 ;; esac
    identity_output=\"\$(PATH=\"\$minimal_path\" ./result/libexec/sshfling/sshfling-unix-identity identity root)\"
    case \"\$identity_output\" in *uid=0*) ;; *) exit 1 ;; esac
    version_output=\"\$(PATH=\"\$minimal_path\" ./result/bin/sshfling --version)\"
    test \"\$version_output\" = 'sshfling $version'
    PATH=\"\$minimal_path\" ./result/bin/sshfling --json doctor --dependencies --mode client >/dev/null
    PATH=\"\$minimal_path\" ./result/bin/sshfling --json doctor --dependencies --mode password-server >/dev/null
    PATH=\"\$harness_path\" \"\$harness_bash\" /tmp/validate-native-login-shell.sh ./result/share/sshfling/templates/production/sshfling-login-shell >/dev/null
    PATH=\"\$harness_path\" \"\$harness_bash\" /tmp/validate-native-session-policy.sh ./result/share/sshfling/templates/production/sshfling-session >/dev/null
    PATH=\"\$harness_path\" \"\$harness_bash\" /tmp/validate-cli.sh ./result/bin/sshfling '$version'"
}

phase="${SSHFLING_CONTAINER_TEST_PHASE:-all}"
case "$phase" in
  all)
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
    ;;
  smoke)
    pull_and_smoke_images
    ;;
  compose)
    test_compose_images
    ;;
  compose-build)
    build_compose_images
    ;;
  production)
    test_production_image
    ;;
  roundtrip)
    docker image inspect timed-ssh-server:latest timed-ssh-client:latest >/dev/null
    test_compose_round_trip
    ;;
  debian|ubuntu)
    prepare_artifacts
    test_deb_image "$([[ "$phase" == debian ]] && echo debian:bookworm-slim || echo ubuntu:24.04)"
    ;;
  fedora|rocky|alma|ubi)
    prepare_artifacts
    case "$phase" in
      fedora) image="fedora:latest" ;;
      rocky) image="rockylinux:9" ;;
      alma) image="almalinux:9" ;;
      ubi) image="registry.access.redhat.com/ubi9/ubi" ;;
    esac
    test_rpm_image "$image"
    ;;
  opensuse|arch|alpine|slackware|void|nix)
    prepare_artifacts
    "test_$phase"
    ;;
  *)
    echo "Unknown SSHFLING_CONTAINER_TEST_PHASE: $phase" >&2
    exit 2
    ;;
esac

log "container image test phase passed: $phase"
