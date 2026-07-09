#!/usr/bin/env bash
set -euo pipefail

package_dist="${1:?package dist directory is required}"
public_dir="${2:?public directory is required}"
base_url="${3:?base URL is required}"
repository="${5:?repository is required}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=packaging/version.sh
source "$repo_root/packaging/version.sh"
version="$(assert_sshfling_version_matches_source "${4:?version is required}" "$repo_root")"
manifest_timestamp="${SOURCE_DATE_EPOCH:-}"
if [[ -z "$manifest_timestamp" ]]; then
  manifest_timestamp="$(git -C "$repo_root" log -1 --format=%ct 2>/dev/null || date -u +%s)"
fi

owner="${repository%%/*}"
release_url="https://github.com/${repository}/releases/download/v${version}"
source_tar="sshfling-${version}.tar.gz"
source_path="${public_dir}/downloads/${source_tar}"
maintainer="GRWLX <44076838+GRWLX@users.noreply.github.com>"

if [[ ! -d "$package_dist" ]]; then
  echo "Package dist directory does not exist: $package_dist" >&2
  exit 2
fi

first_file_optional() {
  local dir="$1"
  local pattern="$2"
  find "$dir" -maxdepth 1 -type f -name "$pattern" -print | sort | head -n 1
}

hash_file() {
  local algorithm="$1"
  local path="$2"
  "${algorithm}sum" "$path" | awk '{print $1}'
}

file_size() {
  wc -c <"$1" | tr -d '[:space:]'
}

python_hashes() {
  python3 - "$source_path" <<'PY'
import base64
import hashlib
import sys

path = sys.argv[1]
data = open(path, "rb").read()
sha256 = hashlib.sha256(data).digest()
alphabet = "0123456789abcdfghijklmnpqrsvwxyz"

def nix_base32(raw):
    length = (len(raw) * 8 + 4) // 5
    chars = []
    for index in range(length - 1, -1, -1):
        bit = index * 5
        byte_index = bit // 8
        shift = bit % 8
        value = raw[byte_index] >> shift
        if byte_index + 1 < len(raw):
            value |= raw[byte_index + 1] << (8 - shift)
        chars.append(alphabet[value & 31])
    return "".join(chars)

print(hashlib.blake2s(data).hexdigest())
print("sha256-" + base64.b64encode(sha256).decode("ascii"))
print(nix_base32(sha256))
PY
}

source_sha="$(hash_file sha256 "$source_path")"
source_sha512="$(hash_file sha512 "$source_path")"
source_size="$(file_size "$source_path")"
readarray -t derived_hashes < <(python_hashes)
source_blake2s="${derived_hashes[0]}"
source_sri="${derived_hashes[1]}"
source_nix32="${derived_hashes[2]}"

msi_path="$(first_file_optional "$public_dir/downloads" "sshfling-${version}.msi")"
windows_zip_path="$(first_file_optional "$public_dir/downloads" "sshfling-${version}-windows.zip")"
msi_name=""
msi_sha=""
msi_sha_upper=""
windows_zip_name=""
windows_zip_sha=""
if [[ -n "$msi_path" ]]; then
  msi_name="$(basename "$msi_path")"
  msi_sha="$(hash_file sha256 "$msi_path")"
  msi_sha_upper="$(printf '%s' "$msi_sha" | tr '[:lower:]' '[:upper:]')"
fi
if [[ -n "$windows_zip_path" ]]; then
  windows_zip_name="$(basename "$windows_zip_path")"
  windows_zip_sha="$(hash_file sha256 "$windows_zip_path")"
fi

install -d \
  "$public_dir/arch" \
  "$public_dir/alpine" \
  "$public_dir/freebsd/security/sshfling/files" \
  "$public_dir/openbsd/security/sshfling/pkg" \
  "$public_dir/pkgsrc/security/sshfling" \
  "$public_dir/nix" \
  "$public_dir/guix" \
  "$public_dir/void" \
  "$public_dir/gentoo/app-admin/sshfling" \
  "$public_dir/slackware" \
  "$public_dir/opensuse" \
  "$public_dir/snap" \
  "$public_dir/termux/packages/sshfling" \
  "$public_dir/appimage" \
  "$public_dir/scoop" \
  "$public_dir/winget/manifests/g/${owner}/SSHFling/${version}" \
  "$public_dir/chocolatey/tools"

cat >"$public_dir/arch/PKGBUILD" <<PKGBUILD
pkgname=sshfling
pkgver=${version}
pkgrel=1
pkgdesc="Temporary SSH access broker and CLI"
arch=('any')
url="${base_url}"
license=('LicenseRef-SSHFling-Commercial')
depends=('bash' 'python' 'openssh' 'openssl' 'shadow' 'procps-ng' 'util-linux' 'jq')
optdepends=('docker: Docker Compose test harness')
backup=('etc/sshfling/policy.json')
source=("\${pkgname}-\${pkgver}.tar.gz::${base_url}/downloads/${source_tar}")
sha256sums=('${source_sha}')

package() {
  cd "\${srcdir}/\${pkgname}-\${pkgver}"
  install -Dm755 bin/sshfling "\${pkgdir}/usr/bin/sshfling"
  install -Dm755 native/sshfling-linux-account "\${pkgdir}/usr/libexec/sshfling/sshfling-linux-account"
  install -Dm755 native/sshfling-unix-identity "\${pkgdir}/usr/libexec/sshfling/sshfling-unix-identity"
  install -Dm755 production/sshfling-session "\${pkgdir}/usr/share/sshfling/templates/production/sshfling-session"
  install -Dm644 packaging/policy.json "\${pkgdir}/etc/sshfling/policy.json"
  install -Dm644 systemd/sshflingd.service "\${pkgdir}/usr/lib/systemd/system/sshflingd.service"
  install -Dm644 systemd/sshfling-prune.service "\${pkgdir}/usr/lib/systemd/system/sshfling-prune.service"
  install -Dm644 systemd/sshfling-prune.timer "\${pkgdir}/usr/lib/systemd/system/sshfling-prune.timer"
  install -Dm644 systemd/sshflingd.env.example "\${pkgdir}/usr/share/doc/sshfling/sshflingd.env.example"
  install -Dm644 LICENSE "\${pkgdir}/usr/share/licenses/sshfling/LICENSE"
  install -Dm644 README.md "\${pkgdir}/usr/share/doc/sshfling/README.md"
  install -d "\${pkgdir}/usr/share/sshfling/templates"
  cp -a .env.example LICENSE README.md compose.server.yml compose.client.yml native scripts secrets ssh-client ssh-server production systemd "\${pkgdir}/usr/share/sshfling/templates/"
}
PKGBUILD

cat >"$public_dir/arch/.SRCINFO" <<SRCINFO
pkgbase = sshfling
	pkgdesc = Temporary SSH access broker and CLI
	pkgver = ${version}
	pkgrel = 1
	url = ${base_url}
	arch = any
	license = LicenseRef-SSHFling-Commercial
	depends = python
	depends = bash
	depends = openssh
	depends = openssl
	depends = shadow
	depends = procps-ng
	depends = util-linux
	depends = jq
	optdepends = docker: Docker Compose test harness
	backup = etc/sshfling/policy.json
	source = sshfling-${version}.tar.gz::${base_url}/downloads/${source_tar}
	sha256sums = ${source_sha}

pkgname = sshfling
SRCINFO

cat >"$public_dir/alpine/APKBUILD" <<APKBUILD
# Contributor: ${maintainer}
# Maintainer: ${maintainer}
pkgname=sshfling
pkgver=${version}
pkgrel=0
pkgdesc="Temporary SSH access broker and CLI"
url="${base_url}"
arch="noarch"
license="LicenseRef-SSHFling-Commercial"
depends="bash python3 openssh-client openssl shadow procps util-linux jq"
options="!check"
source="\$pkgname-\$pkgver.tar.gz::${base_url}/downloads/${source_tar}"
builddir="\$srcdir/\$pkgname-\$pkgver"

package() {
	install -Dm755 "\$builddir/bin/sshfling" "\$pkgdir/usr/bin/sshfling"
	install -Dm755 "\$builddir/native/sshfling-linux-account" "\$pkgdir/usr/libexec/sshfling/sshfling-linux-account"
	install -Dm755 "\$builddir/native/sshfling-unix-identity" "\$pkgdir/usr/libexec/sshfling/sshfling-unix-identity"
	install -Dm755 "\$builddir/production/sshfling-session" "\$pkgdir/usr/share/sshfling/templates/production/sshfling-session"
	install -Dm644 "\$builddir/packaging/policy.json" "\$pkgdir/etc/sshfling/policy.json"
	install -Dm644 "\$builddir/LICENSE" "\$pkgdir/usr/share/licenses/sshfling/LICENSE"
	install -Dm644 "\$builddir/README.md" "\$pkgdir/usr/share/doc/sshfling/README.md"
	mkdir -p "\$pkgdir/usr/share/sshfling/templates"
	cp -a "\$builddir"/.env.example "\$builddir"/LICENSE "\$builddir"/README.md "\$builddir"/compose.server.yml "\$builddir"/compose.client.yml \
		"\$builddir"/native "\$builddir"/scripts "\$builddir"/secrets "\$builddir"/ssh-client "\$builddir"/ssh-server "\$builddir"/production "\$builddir"/systemd \
		"\$pkgdir/usr/share/sshfling/templates/"
}

sha512sums="
${source_sha512}  \$pkgname-\$pkgver.tar.gz
"
APKBUILD

cat >"$public_dir/freebsd/security/sshfling/Makefile" <<MAKEFILE
PORTNAME=	sshfling
DISTVERSION=	${version}
CATEGORIES=	security sysutils
MASTER_SITES=	${base_url}/downloads/

MAINTAINER=	44076838+GRWLX@users.noreply.github.com
COMMENT=	Temporary SSH access broker and CLI
WWW=		${base_url}

LICENSE=	SSHFLING_COMMERCIAL
LICENSE_NAME=	SSHFling Commercial License
LICENSE_FILE=	\${WRKSRC}/LICENSE
LICENSE_PERMS=	no-dist-mirror no-dist-sell no-pkg-mirror no-pkg-sell no-auto-accept

RUN_DEPENDS=	python3:lang/python3 bash:shells/bash jq:textproc/jq

USES=		python shebangfix
SHEBANG_FILES=	bin/sshfling
NO_BUILD=	yes

post-patch:
	\${REINPLACE_CMD} -e 's|/etc/sshfling/policy.json|\${PREFIX}/etc/sshfling/policy.json|g' \
		\${WRKSRC}/bin/sshfling \${WRKSRC}/production/sshfling-session

do-install:
	\${INSTALL_SCRIPT} \${WRKSRC}/bin/sshfling \${STAGEDIR}\${PREFIX}/bin/sshfling
	\${MKDIR} \${STAGEDIR}\${PREFIX}/libexec/sshfling
	\${INSTALL_SCRIPT} \${WRKSRC}/native/sshfling-unix-identity \${STAGEDIR}\${PREFIX}/libexec/sshfling/sshfling-unix-identity
	\${MKDIR} \${STAGEDIR}\${PREFIX}/etc/sshfling
	\${INSTALL_DATA} \${WRKSRC}/packaging/policy.json \${STAGEDIR}\${PREFIX}/etc/sshfling/policy.json.sample
	\${MKDIR} \${STAGEDIR}\${DOCSDIR}
	\${INSTALL_DATA} \${WRKSRC}/README.md \${WRKSRC}/LICENSE \${STAGEDIR}\${DOCSDIR}/
	\${MKDIR} \${STAGEDIR}\${PREFIX}/share/sshfling/templates/scripts
	\${MKDIR} \${STAGEDIR}\${PREFIX}/share/sshfling/templates/native
	\${MKDIR} \${STAGEDIR}\${PREFIX}/share/sshfling/templates/secrets
	\${MKDIR} \${STAGEDIR}\${PREFIX}/share/sshfling/templates/ssh-client
	\${MKDIR} \${STAGEDIR}\${PREFIX}/share/sshfling/templates/ssh-server
	\${MKDIR} \${STAGEDIR}\${PREFIX}/share/sshfling/templates/production
	\${MKDIR} \${STAGEDIR}\${PREFIX}/share/sshfling/templates/systemd
	\${INSTALL_DATA} \${WRKSRC}/.env.example \${STAGEDIR}\${PREFIX}/share/sshfling/templates/.env.example
	\${INSTALL_DATA} \${WRKSRC}/LICENSE \${STAGEDIR}\${PREFIX}/share/sshfling/templates/LICENSE
	\${INSTALL_DATA} \${WRKSRC}/README.md \${STAGEDIR}\${PREFIX}/share/sshfling/templates/README.md
	\${INSTALL_DATA} \${WRKSRC}/compose.server.yml \${STAGEDIR}\${PREFIX}/share/sshfling/templates/compose.server.yml
	\${INSTALL_DATA} \${WRKSRC}/compose.client.yml \${STAGEDIR}\${PREFIX}/share/sshfling/templates/compose.client.yml
	\${INSTALL_SCRIPT} \${WRKSRC}/scripts/install-local.sh \${STAGEDIR}\${PREFIX}/share/sshfling/templates/scripts/install-local.sh
	\${INSTALL_SCRIPT} \${WRKSRC}/scripts/uninstall-local.sh \${STAGEDIR}\${PREFIX}/share/sshfling/templates/scripts/uninstall-local.sh
	\${INSTALL_SCRIPT} \${WRKSRC}/scripts/create-network.sh \${STAGEDIR}\${PREFIX}/share/sshfling/templates/scripts/create-network.sh
	\${INSTALL_SCRIPT} \${WRKSRC}/scripts/generate-ssh-key.sh \${STAGEDIR}\${PREFIX}/share/sshfling/templates/scripts/generate-ssh-key.sh
	\${INSTALL_SCRIPT} \${WRKSRC}/native/sshfling-linux-account \${STAGEDIR}\${PREFIX}/share/sshfling/templates/native/sshfling-linux-account
	\${INSTALL_SCRIPT} \${WRKSRC}/native/sshfling-unix-identity \${STAGEDIR}\${PREFIX}/share/sshfling/templates/native/sshfling-unix-identity
	\${INSTALL_DATA} \${WRKSRC}/secrets/.gitkeep \${STAGEDIR}\${PREFIX}/share/sshfling/templates/secrets/.gitkeep
	\${INSTALL_DATA} \${WRKSRC}/ssh-client/Dockerfile \${STAGEDIR}\${PREFIX}/share/sshfling/templates/ssh-client/Dockerfile
	\${INSTALL_SCRIPT} \${WRKSRC}/ssh-client/entrypoint.sh \${STAGEDIR}\${PREFIX}/share/sshfling/templates/ssh-client/entrypoint.sh
	\${INSTALL_DATA} \${WRKSRC}/ssh-server/Dockerfile \${STAGEDIR}\${PREFIX}/share/sshfling/templates/ssh-server/Dockerfile
	\${INSTALL_SCRIPT} \${WRKSRC}/ssh-server/entrypoint.sh \${STAGEDIR}\${PREFIX}/share/sshfling/templates/ssh-server/entrypoint.sh
	\${INSTALL_SCRIPT} \${WRKSRC}/ssh-server/limited-session.sh \${STAGEDIR}\${PREFIX}/share/sshfling/templates/ssh-server/limited-session.sh
	\${INSTALL_DATA} \${WRKSRC}/ssh-server/sshd_config \${STAGEDIR}\${PREFIX}/share/sshfling/templates/ssh-server/sshd_config
	\${INSTALL_SCRIPT} \${WRKSRC}/production/sshfling-session \${STAGEDIR}\${PREFIX}/share/sshfling/templates/production/sshfling-session
	\${INSTALL_DATA} \${WRKSRC}/systemd/sshflingd.service \${STAGEDIR}\${PREFIX}/share/sshfling/templates/systemd/sshflingd.service
	\${INSTALL_DATA} \${WRKSRC}/systemd/sshfling-prune.service \${STAGEDIR}\${PREFIX}/share/sshfling/templates/systemd/sshfling-prune.service
	\${INSTALL_DATA} \${WRKSRC}/systemd/sshfling-prune.timer \${STAGEDIR}\${PREFIX}/share/sshfling/templates/systemd/sshfling-prune.timer
	\${INSTALL_DATA} \${WRKSRC}/systemd/sshflingd.env.example \${STAGEDIR}\${PREFIX}/share/sshfling/templates/systemd/sshflingd.env.example

.include <bsd.port.mk>
MAKEFILE

cat >"$public_dir/freebsd/security/sshfling/distinfo" <<DISTINFO
TIMESTAMP = ${manifest_timestamp}
SHA256 (${source_tar}) = ${source_sha}
SIZE (${source_tar}) = ${source_size}
DISTINFO

cat >"$public_dir/freebsd/security/sshfling/pkg-descr" <<PKGDESCR
SSHFling grants short-lived SSH access with default password grants, optional
OpenSSH user certificates, and a forced session wrapper so temporary SSH
sessions are capped by a server-side wall-clock timeout.
PKGDESCR

cat >"$public_dir/freebsd/security/sshfling/pkg-plist" <<PLIST
bin/sshfling
libexec/sshfling/sshfling-unix-identity
@sample etc/sshfling/policy.json.sample
share/sshfling/templates/.env.example
share/sshfling/templates/LICENSE
share/sshfling/templates/README.md
share/sshfling/templates/compose.client.yml
share/sshfling/templates/compose.server.yml
share/sshfling/templates/production/sshfling-session
share/sshfling/templates/native/sshfling-linux-account
share/sshfling/templates/native/sshfling-unix-identity
share/sshfling/templates/scripts/create-network.sh
share/sshfling/templates/scripts/generate-ssh-key.sh
share/sshfling/templates/scripts/install-local.sh
share/sshfling/templates/scripts/uninstall-local.sh
share/sshfling/templates/secrets/.gitkeep
share/sshfling/templates/ssh-client/Dockerfile
share/sshfling/templates/ssh-client/entrypoint.sh
share/sshfling/templates/ssh-server/Dockerfile
share/sshfling/templates/ssh-server/entrypoint.sh
share/sshfling/templates/ssh-server/limited-session.sh
share/sshfling/templates/ssh-server/sshd_config
share/sshfling/templates/systemd/sshflingd.env.example
share/sshfling/templates/systemd/sshfling-prune.service
share/sshfling/templates/systemd/sshfling-prune.timer
share/sshfling/templates/systemd/sshflingd.service
%%DOCSDIR%%/LICENSE
%%DOCSDIR%%/README.md
PLIST

openbsd_sha="$(openssl dgst -sha256 -binary "$source_path" | base64 | tr -d '\n')"
cat >"$public_dir/openbsd/security/sshfling/Makefile" <<MAKEFILE
COMMENT =	temporary SSH access broker and CLI
DISTNAME =	sshfling-${version}
CATEGORIES =	security sysutils

HOMEPAGE =	${base_url}
MAINTAINER =	${maintainer}

# SSHFling Commercial License: redistribution requires prior written permission.
PERMIT_PACKAGE =	requires prior written permission from GRWLX
PERMIT_DISTFILES =	requires prior written permission from GRWLX

MASTER_SITES =	${base_url}/downloads/

MODULES =	lang/python
RUN_DEPENDS =	shells/bash textproc/jq
NO_BUILD =	Yes

do-install:
	\${INSTALL_SCRIPT} \${WRKSRC}/bin/sshfling \${PREFIX}/bin/sshfling
	\${INSTALL_DATA_DIR} \${PREFIX}/libexec/sshfling
	\${INSTALL_SCRIPT} \${WRKSRC}/native/sshfling-unix-identity \${PREFIX}/libexec/sshfling/sshfling-unix-identity
	\${INSTALL_DATA_DIR} \${PREFIX}/share/doc/sshfling
	\${INSTALL_DATA} \${WRKSRC}/README.md \${WRKSRC}/LICENSE \${PREFIX}/share/doc/sshfling/
	\${INSTALL_DATA_DIR} \${PREFIX}/share/examples/sshfling
	\${INSTALL_DATA} \${WRKSRC}/packaging/policy.json \${PREFIX}/share/examples/sshfling/policy.json
	\${INSTALL_DATA_DIR} \${PREFIX}/share/sshfling/templates/scripts
	\${INSTALL_DATA_DIR} \${PREFIX}/share/sshfling/templates/native
	\${INSTALL_DATA_DIR} \${PREFIX}/share/sshfling/templates/secrets
	\${INSTALL_DATA_DIR} \${PREFIX}/share/sshfling/templates/ssh-client
	\${INSTALL_DATA_DIR} \${PREFIX}/share/sshfling/templates/ssh-server
	\${INSTALL_DATA_DIR} \${PREFIX}/share/sshfling/templates/production
	\${INSTALL_DATA_DIR} \${PREFIX}/share/sshfling/templates/systemd
	\${INSTALL_DATA} \${WRKSRC}/.env.example \${PREFIX}/share/sshfling/templates/.env.example
	\${INSTALL_DATA} \${WRKSRC}/LICENSE \${PREFIX}/share/sshfling/templates/LICENSE
	\${INSTALL_DATA} \${WRKSRC}/README.md \${PREFIX}/share/sshfling/templates/README.md
	\${INSTALL_DATA} \${WRKSRC}/compose.server.yml \${PREFIX}/share/sshfling/templates/compose.server.yml
	\${INSTALL_DATA} \${WRKSRC}/compose.client.yml \${PREFIX}/share/sshfling/templates/compose.client.yml
	\${INSTALL_SCRIPT} \${WRKSRC}/scripts/install-local.sh \${PREFIX}/share/sshfling/templates/scripts/install-local.sh
	\${INSTALL_SCRIPT} \${WRKSRC}/scripts/uninstall-local.sh \${PREFIX}/share/sshfling/templates/scripts/uninstall-local.sh
	\${INSTALL_SCRIPT} \${WRKSRC}/scripts/create-network.sh \${PREFIX}/share/sshfling/templates/scripts/create-network.sh
	\${INSTALL_SCRIPT} \${WRKSRC}/scripts/generate-ssh-key.sh \${PREFIX}/share/sshfling/templates/scripts/generate-ssh-key.sh
	\${INSTALL_SCRIPT} \${WRKSRC}/native/sshfling-linux-account \${PREFIX}/share/sshfling/templates/native/sshfling-linux-account
	\${INSTALL_SCRIPT} \${WRKSRC}/native/sshfling-unix-identity \${PREFIX}/share/sshfling/templates/native/sshfling-unix-identity
	\${INSTALL_DATA} \${WRKSRC}/secrets/.gitkeep \${PREFIX}/share/sshfling/templates/secrets/.gitkeep
	\${INSTALL_DATA} \${WRKSRC}/ssh-client/Dockerfile \${PREFIX}/share/sshfling/templates/ssh-client/Dockerfile
	\${INSTALL_SCRIPT} \${WRKSRC}/ssh-client/entrypoint.sh \${PREFIX}/share/sshfling/templates/ssh-client/entrypoint.sh
	\${INSTALL_DATA} \${WRKSRC}/ssh-server/Dockerfile \${PREFIX}/share/sshfling/templates/ssh-server/Dockerfile
	\${INSTALL_SCRIPT} \${WRKSRC}/ssh-server/entrypoint.sh \${PREFIX}/share/sshfling/templates/ssh-server/entrypoint.sh
	\${INSTALL_SCRIPT} \${WRKSRC}/ssh-server/limited-session.sh \${PREFIX}/share/sshfling/templates/ssh-server/limited-session.sh
	\${INSTALL_DATA} \${WRKSRC}/ssh-server/sshd_config \${PREFIX}/share/sshfling/templates/ssh-server/sshd_config
	\${INSTALL_SCRIPT} \${WRKSRC}/production/sshfling-session \${PREFIX}/share/sshfling/templates/production/sshfling-session
	\${INSTALL_DATA} \${WRKSRC}/systemd/sshflingd.service \${PREFIX}/share/sshfling/templates/systemd/sshflingd.service
	\${INSTALL_DATA} \${WRKSRC}/systemd/sshfling-prune.service \${PREFIX}/share/sshfling/templates/systemd/sshfling-prune.service
	\${INSTALL_DATA} \${WRKSRC}/systemd/sshfling-prune.timer \${PREFIX}/share/sshfling/templates/systemd/sshfling-prune.timer
	\${INSTALL_DATA} \${WRKSRC}/systemd/sshflingd.env.example \${PREFIX}/share/sshfling/templates/systemd/sshflingd.env.example

.include <bsd.port.mk>
MAKEFILE

cat >"$public_dir/openbsd/security/sshfling/distinfo" <<DISTINFO
SHA256 (${source_tar}) = ${openbsd_sha}
SIZE (${source_tar}) = ${source_size}
DISTINFO

cat >"$public_dir/openbsd/security/sshfling/pkg/DESCR" <<DESCR
SSHFling grants short-lived SSH access with default password grants, optional
OpenSSH user certificates, and a forced session wrapper so temporary SSH
sessions are capped by a server-side wall-clock timeout.
DESCR

cat >"$public_dir/openbsd/security/sshfling/pkg/PLIST" <<PLIST
@bin bin/sshfling
@bin libexec/sshfling/sshfling-unix-identity
@sample \${SYSCONFDIR}/sshfling/
share/examples/sshfling/policy.json
@sample \${SYSCONFDIR}/sshfling/policy.json
share/sshfling/templates/.env.example
share/sshfling/templates/LICENSE
share/sshfling/templates/README.md
share/sshfling/templates/compose.client.yml
share/sshfling/templates/compose.server.yml
share/sshfling/templates/production/sshfling-session
share/sshfling/templates/native/sshfling-linux-account
share/sshfling/templates/native/sshfling-unix-identity
share/sshfling/templates/scripts/create-network.sh
share/sshfling/templates/scripts/generate-ssh-key.sh
share/sshfling/templates/scripts/install-local.sh
share/sshfling/templates/scripts/uninstall-local.sh
share/sshfling/templates/secrets/.gitkeep
share/sshfling/templates/ssh-client/Dockerfile
share/sshfling/templates/ssh-client/entrypoint.sh
share/sshfling/templates/ssh-server/Dockerfile
share/sshfling/templates/ssh-server/entrypoint.sh
share/sshfling/templates/ssh-server/limited-session.sh
share/sshfling/templates/ssh-server/sshd_config
share/sshfling/templates/systemd/sshflingd.env.example
share/sshfling/templates/systemd/sshfling-prune.service
share/sshfling/templates/systemd/sshfling-prune.timer
share/sshfling/templates/systemd/sshflingd.service
share/doc/sshfling/LICENSE
share/doc/sshfling/README.md
PLIST

cat >"$public_dir/pkgsrc/security/sshfling/Makefile" <<MAKEFILE
# \$NetBSD\$

DISTNAME=	sshfling-${version}
CATEGORIES=	security sysutils
MASTER_SITES=	${base_url}/downloads/

MAINTAINER=	44076838+GRWLX@users.noreply.github.com
HOMEPAGE=	${base_url}
COMMENT=	Temporary SSH access broker and CLI
LICENSE=	sshfling-commercial-license

USE_LANGUAGES=	# none
NO_BUILD=	yes
DEPENDS+=	jq-[0-9]*:../../devel/jq
DEPENDS+=	bash-[0-9]*:../../shells/bash
REPLACE_PYTHON=	bin/sshfling
PKG_SYSCONFSUBDIR=	sshfling
EGDIR=		\${PREFIX}/share/examples/sshfling
CONF_FILES=	\${EGDIR}/policy.json \${PKG_SYSCONFDIR}/policy.json
SUBST_CLASSES+=	sshfling-paths
SUBST_STAGE.sshfling-paths=	pre-configure
SUBST_FILES.sshfling-paths=	bin/sshfling production/sshfling-session
SUBST_SED.sshfling-paths=	-e 's|/etc/sshfling/policy.json|\${PKG_SYSCONFDIR}/policy.json|g'
INSTALLATION_DIRS=	bin libexec libexec/sshfling share/doc/sshfling share/examples/sshfling share/sshfling/templates share/sshfling/templates/native share/sshfling/templates/scripts share/sshfling/templates/secrets share/sshfling/templates/ssh-client share/sshfling/templates/ssh-server share/sshfling/templates/production share/sshfling/templates/systemd

do-install:
	\${INSTALL_SCRIPT} \${WRKSRC}/bin/sshfling \${DESTDIR}\${PREFIX}/bin/sshfling
	\${INSTALL_SCRIPT} \${WRKSRC}/native/sshfling-unix-identity \${DESTDIR}\${PREFIX}/libexec/sshfling/sshfling-unix-identity
	\${INSTALL_DATA} \${WRKSRC}/README.md \${DESTDIR}\${PREFIX}/share/doc/sshfling/README.md
	\${INSTALL_DATA} \${WRKSRC}/LICENSE \${DESTDIR}\${PREFIX}/share/doc/sshfling/LICENSE
	\${INSTALL_DATA} \${WRKSRC}/packaging/policy.json \${DESTDIR}\${EGDIR}/policy.json
	\${INSTALL_DATA} \${WRKSRC}/.env.example \${DESTDIR}\${PREFIX}/share/sshfling/templates/.env.example
	\${INSTALL_DATA} \${WRKSRC}/LICENSE \${DESTDIR}\${PREFIX}/share/sshfling/templates/LICENSE
	\${INSTALL_DATA} \${WRKSRC}/README.md \${DESTDIR}\${PREFIX}/share/sshfling/templates/README.md
	\${INSTALL_DATA} \${WRKSRC}/compose.server.yml \${DESTDIR}\${PREFIX}/share/sshfling/templates/compose.server.yml
	\${INSTALL_DATA} \${WRKSRC}/compose.client.yml \${DESTDIR}\${PREFIX}/share/sshfling/templates/compose.client.yml
	\${INSTALL_SCRIPT} \${WRKSRC}/scripts/install-local.sh \${DESTDIR}\${PREFIX}/share/sshfling/templates/scripts/install-local.sh
	\${INSTALL_SCRIPT} \${WRKSRC}/scripts/uninstall-local.sh \${DESTDIR}\${PREFIX}/share/sshfling/templates/scripts/uninstall-local.sh
	\${INSTALL_SCRIPT} \${WRKSRC}/scripts/create-network.sh \${DESTDIR}\${PREFIX}/share/sshfling/templates/scripts/create-network.sh
	\${INSTALL_SCRIPT} \${WRKSRC}/scripts/generate-ssh-key.sh \${DESTDIR}\${PREFIX}/share/sshfling/templates/scripts/generate-ssh-key.sh
	\${INSTALL_SCRIPT} \${WRKSRC}/native/sshfling-linux-account \${DESTDIR}\${PREFIX}/share/sshfling/templates/native/sshfling-linux-account
	\${INSTALL_SCRIPT} \${WRKSRC}/native/sshfling-unix-identity \${DESTDIR}\${PREFIX}/share/sshfling/templates/native/sshfling-unix-identity
	\${INSTALL_DATA} \${WRKSRC}/secrets/.gitkeep \${DESTDIR}\${PREFIX}/share/sshfling/templates/secrets/.gitkeep
	\${INSTALL_DATA} \${WRKSRC}/ssh-client/Dockerfile \${DESTDIR}\${PREFIX}/share/sshfling/templates/ssh-client/Dockerfile
	\${INSTALL_SCRIPT} \${WRKSRC}/ssh-client/entrypoint.sh \${DESTDIR}\${PREFIX}/share/sshfling/templates/ssh-client/entrypoint.sh
	\${INSTALL_DATA} \${WRKSRC}/ssh-server/Dockerfile \${DESTDIR}\${PREFIX}/share/sshfling/templates/ssh-server/Dockerfile
	\${INSTALL_SCRIPT} \${WRKSRC}/ssh-server/entrypoint.sh \${DESTDIR}\${PREFIX}/share/sshfling/templates/ssh-server/entrypoint.sh
	\${INSTALL_SCRIPT} \${WRKSRC}/ssh-server/limited-session.sh \${DESTDIR}\${PREFIX}/share/sshfling/templates/ssh-server/limited-session.sh
	\${INSTALL_DATA} \${WRKSRC}/ssh-server/sshd_config \${DESTDIR}\${PREFIX}/share/sshfling/templates/ssh-server/sshd_config
	\${INSTALL_SCRIPT} \${WRKSRC}/production/sshfling-session \${DESTDIR}\${PREFIX}/share/sshfling/templates/production/sshfling-session
	\${INSTALL_DATA} \${WRKSRC}/systemd/sshflingd.service \${DESTDIR}\${PREFIX}/share/sshfling/templates/systemd/sshflingd.service
	\${INSTALL_DATA} \${WRKSRC}/systemd/sshfling-prune.service \${DESTDIR}\${PREFIX}/share/sshfling/templates/systemd/sshfling-prune.service
	\${INSTALL_DATA} \${WRKSRC}/systemd/sshfling-prune.timer \${DESTDIR}\${PREFIX}/share/sshfling/templates/systemd/sshfling-prune.timer
	\${INSTALL_DATA} \${WRKSRC}/systemd/sshflingd.env.example \${DESTDIR}\${PREFIX}/share/sshfling/templates/systemd/sshflingd.env.example

.include "../../lang/python/application.mk"
.include "../../mk/bsd.pkg.mk"
MAKEFILE

cat >"$public_dir/pkgsrc/security/sshfling/DESCR" <<DESCR
SSHFling grants short-lived SSH access with default password grants, optional
OpenSSH user certificates, and a forced session wrapper so temporary SSH
sessions are capped by a server-side wall-clock timeout.
DESCR

cat >"$public_dir/pkgsrc/security/sshfling/PLIST" <<PLIST
@comment \$NetBSD\$
bin/sshfling
libexec/sshfling/sshfling-unix-identity
share/sshfling/templates/.env.example
share/sshfling/templates/LICENSE
share/sshfling/templates/README.md
share/sshfling/templates/compose.client.yml
share/sshfling/templates/compose.server.yml
share/sshfling/templates/production/sshfling-session
share/sshfling/templates/native/sshfling-linux-account
share/sshfling/templates/native/sshfling-unix-identity
share/sshfling/templates/scripts/create-network.sh
share/sshfling/templates/scripts/generate-ssh-key.sh
share/sshfling/templates/scripts/install-local.sh
share/sshfling/templates/scripts/uninstall-local.sh
share/sshfling/templates/secrets/.gitkeep
share/sshfling/templates/ssh-client/Dockerfile
share/sshfling/templates/ssh-client/entrypoint.sh
share/sshfling/templates/ssh-server/Dockerfile
share/sshfling/templates/ssh-server/entrypoint.sh
share/sshfling/templates/ssh-server/limited-session.sh
share/sshfling/templates/ssh-server/sshd_config
share/sshfling/templates/systemd/sshflingd.env.example
share/sshfling/templates/systemd/sshfling-prune.service
share/sshfling/templates/systemd/sshfling-prune.timer
share/sshfling/templates/systemd/sshflingd.service
share/doc/sshfling/LICENSE
share/doc/sshfling/README.md
share/examples/sshfling/policy.json
PLIST

cat >"$public_dir/pkgsrc/security/sshfling/distinfo" <<DISTINFO
\$NetBSD\$

BLAKE2s (${source_tar}) = ${source_blake2s}
SHA512 (${source_tar}) = ${source_sha512}
Size (${source_tar}) = ${source_size} bytes
DISTINFO

cat >"$public_dir/nix/flake.nix" <<NIX
{
  description = "SSHFling temporary SSH access broker and CLI";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          runtimePath = [ pkgs.bash pkgs.python3 pkgs.openssh pkgs.openssl pkgs.jq pkgs.procps pkgs.util-linux ] ++ pkgs.lib.optionals pkgs.stdenv.isLinux [ pkgs.shadow ];
        in {
          default = pkgs.stdenvNoCC.mkDerivation {
            pname = "sshfling";
            version = "${version}";
            src = pkgs.fetchurl {
              url = "${base_url}/downloads/${source_tar}";
              hash = "${source_sri}";
            };
            nativeBuildInputs = [ pkgs.makeWrapper ];
            dontBuild = true;
            installPhase = ''
              runHook preInstall
              install -Dm755 bin/sshfling \$out/bin/sshfling
              install -Dm755 native/sshfling-linux-account \$out/libexec/sshfling/sshfling-linux-account
              install -Dm755 native/sshfling-unix-identity \$out/libexec/sshfling/sshfling-unix-identity
              install -Dm755 production/sshfling-session \$out/share/sshfling/templates/production/sshfling-session
              install -Dm644 LICENSE \$out/share/doc/sshfling/LICENSE
              install -Dm644 README.md \$out/share/doc/sshfling/README.md
              mkdir -p \$out/share/sshfling/templates
              cp -a .env.example LICENSE README.md compose.server.yml compose.client.yml native scripts secrets ssh-client ssh-server production systemd \$out/share/sshfling/templates/
              patchShebangs \$out/bin/sshfling
              patchShebangs \$out/libexec/sshfling/sshfling-linux-account
              patchShebangs \$out/libexec/sshfling/sshfling-unix-identity
              wrapProgram \$out/bin/sshfling \
                --prefix PATH : \${pkgs.lib.makeBinPath runtimePath} \
                --set SSHFLING_LINUX_ACCOUNT_HELPER \$out/libexec/sshfling/sshfling-linux-account \
                --set SSHFLING_UNIX_IDENTITY_HELPER \$out/libexec/sshfling/sshfling-unix-identity
              runHook postInstall
            '';
            meta = with pkgs.lib; {
              description = "Temporary SSH access broker and CLI";
              homepage = "${base_url}";
              license = licenses.unfree;
              mainProgram = "sshfling";
              platforms = platforms.unix;
            };
          };
        });
      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "\${self.packages.\${system}.default}/bin/sshfling";
        };
      });
    };
}
NIX

cat >"$public_dir/guix/sshfling.scm" <<GUIX
(define-module (sshfling)
  #:use-module (guix packages)
  #:use-module (guix download)
  #:use-module (guix build-system copy)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (gnu packages admin)
  #:use-module (gnu packages bash)
  #:use-module (gnu packages linux)
  #:use-module (gnu packages python)
  #:use-module (gnu packages ssh)
  #:use-module (gnu packages tls)
  #:use-module (gnu packages web))

(define-public sshfling
  (package
    (name "sshfling")
    (version "${version}")
    (source
     (origin
       (method url-fetch)
       (uri "${base_url}/downloads/${source_tar}")
       (sha256 (base32 "${source_nix32}"))))
    (build-system copy-build-system)
    (arguments
     '(#:install-plan
       '(("bin/sshfling" "bin/sshfling")
         ("native/sshfling-linux-account" "libexec/sshfling/sshfling-linux-account")
         ("native/sshfling-unix-identity" "libexec/sshfling/sshfling-unix-identity")
         ("native" "share/sshfling/templates/native")
         ("README.md" "share/doc/sshfling/README.md")
         ("LICENSE" "share/doc/sshfling/LICENSE")
         ("packaging/policy.json" "etc/sshfling/policy.json")
         (".env.example" "share/sshfling/templates/.env.example")
         ("LICENSE" "share/sshfling/templates/LICENSE")
         ("README.md" "share/sshfling/templates/README.md")
         ("compose.server.yml" "share/sshfling/templates/compose.server.yml")
         ("compose.client.yml" "share/sshfling/templates/compose.client.yml")
         ("scripts" "share/sshfling/templates/scripts")
         ("secrets" "share/sshfling/templates/secrets")
         ("ssh-client" "share/sshfling/templates/ssh-client")
         ("ssh-server" "share/sshfling/templates/ssh-server")
         ("production" "share/sshfling/templates/production")
         ("systemd" "share/sshfling/templates/systemd"))))
    (propagated-inputs (list bash-minimal python openssh openssl shadow procps util-linux jq))
    (home-page "${base_url}")
    (synopsis "Temporary SSH access broker and CLI")
    (description
     "SSHFling grants short-lived SSH access with default password grants, optional OpenSSH user certificates, and a forced session wrapper so temporary SSH sessions are capped by a server-side wall-clock timeout.")
    (license #f)))

sshfling
GUIX

cat >"$public_dir/void/template" <<VOID
# Template file for 'sshfling'
pkgname=sshfling
version=${version}
revision=1
depends="bash python3 openssh openssl shadow procps-ng util-linux jq"
short_desc="Temporary SSH access broker and CLI"
maintainer="${maintainer}"
license="LicenseRef-SSHFling-Commercial"
homepage="${base_url}"
distfiles="${base_url}/downloads/${source_tar}"
checksum=${source_sha}

do_install() {
	vbin bin/sshfling
	vinstall native/sshfling-linux-account 755 usr/libexec/sshfling
	vinstall native/sshfling-unix-identity 755 usr/libexec/sshfling
	vinstall production/sshfling-session 755 usr/share/sshfling/templates/production
	vinstall packaging/policy.json 644 etc/sshfling
	vlicense LICENSE
	vdoc README.md
	vmkdir usr/share/sshfling/templates
	for path in .env.example LICENSE README.md compose.server.yml compose.client.yml native scripts secrets ssh-client ssh-server production systemd; do
		vcopy "\$path" usr/share/sshfling/templates
	done
}
VOID

cat >"$public_dir/gentoo/app-admin/sshfling/sshfling-${version}.ebuild" <<GENTOO
EAPI=8

PYTHON_COMPAT=( python3_{10..14} )

inherit python-r1 systemd

DESCRIPTION="Temporary SSH access broker and CLI"
HOMEPAGE="${base_url}"
SRC_URI="${base_url}/downloads/${source_tar}"

LICENSE="LicenseRef-SSHFling-Commercial"
SLOT="0"
KEYWORDS="~amd64 ~arm64"
REQUIRED_USE="\${PYTHON_REQUIRED_USE}"
RDEPEND="\${PYTHON_DEPS}
	app-misc/jq
	app-shells/bash
	dev-libs/openssl
	virtual/ssh
	sys-apps/shadow
	sys-process/procps
	sys-apps/util-linux"

src_install() {
	python_fix_shebang bin/sshfling
	dobin bin/sshfling
	exeinto /usr/libexec/sshfling
	doexe native/sshfling-linux-account
	doexe native/sshfling-unix-identity
	exeinto /usr/share/sshfling/templates/production
	doexe production/sshfling-session
	insinto /etc/sshfling
	doins packaging/policy.json
	systemd_dounit systemd/sshflingd.service systemd/sshfling-prune.service systemd/sshfling-prune.timer
	dodoc README.md
	newdoc LICENSE LICENSE
	insinto /usr/share/sshfling/templates
	doins .env.example LICENSE README.md compose.server.yml compose.client.yml
	doins -r native scripts secrets ssh-client ssh-server production systemd
	fperms 0755 \
		/usr/share/sshfling/templates/native/sshfling-linux-account \
		/usr/share/sshfling/templates/native/sshfling-unix-identity \
		/usr/share/sshfling/templates/scripts/install-local.sh \
		/usr/share/sshfling/templates/scripts/uninstall-local.sh \
		/usr/share/sshfling/templates/scripts/create-network.sh \
		/usr/share/sshfling/templates/scripts/generate-ssh-key.sh \
		/usr/share/sshfling/templates/ssh-client/entrypoint.sh \
		/usr/share/sshfling/templates/ssh-server/entrypoint.sh \
		/usr/share/sshfling/templates/ssh-server/limited-session.sh \
		/usr/share/sshfling/templates/production/sshfling-session
}
GENTOO

cat >"$public_dir/slackware/sshfling.SlackBuild" <<'SLACKBUILD'
#!/bin/sh
set -eu

PRGNAM=sshfling
VERSION=${VERSION:-__VERSION__}
BUILD=${BUILD:-1}
TAG=${TAG:-_SBo}
ARCH=${ARCH:-noarch}
CWD=$(pwd)
TMP=${TMP:-/tmp/SBo}
PKG=$TMP/package-$PRGNAM
OUTPUT=${OUTPUT:-/tmp}

rm -rf "$PKG" "$TMP/$PRGNAM-$VERSION"
mkdir -p "$TMP" "$PKG" "$OUTPUT"
tar xvf "$CWD/$PRGNAM-$VERSION.tar.gz" -C "$TMP"
cd "$TMP/$PRGNAM-$VERSION"

install -Dm755 bin/sshfling "$PKG/usr/bin/sshfling"
install -Dm755 native/sshfling-linux-account "$PKG/usr/libexec/sshfling/sshfling-linux-account"
install -Dm755 native/sshfling-unix-identity "$PKG/usr/libexec/sshfling/sshfling-unix-identity"
install -Dm755 production/sshfling-session "$PKG/usr/share/sshfling/templates/production/sshfling-session"
install -Dm644 packaging/policy.json "$PKG/etc/sshfling/policy.json"
install -Dm644 LICENSE "$PKG/usr/doc/$PRGNAM-$VERSION/LICENSE"
install -Dm644 README.md "$PKG/usr/doc/$PRGNAM-$VERSION/README.md"
mkdir -p "$PKG/usr/share/sshfling/templates"
cp -a .env.example LICENSE README.md compose.server.yml compose.client.yml native scripts secrets ssh-client ssh-server production systemd "$PKG/usr/share/sshfling/templates/"
mkdir -p "$PKG/install"
cat "$CWD/slack-desc" > "$PKG/install/slack-desc"

cd "$PKG"
/sbin/makepkg -l y -c n "$OUTPUT/$PRGNAM-$VERSION-$ARCH-$BUILD$TAG.txz"
SLACKBUILD
sed -i "s/__VERSION__/${version}/g" "$public_dir/slackware/sshfling.SlackBuild"
chmod 0755 "$public_dir/slackware/sshfling.SlackBuild"

cat >"$public_dir/slackware/slack-desc" <<'SLACKDESC'
sshfling: sshfling (temporary SSH access broker)
sshfling:
sshfling: SSHFling grants short-lived SSH access with default password grants,
sshfling: optional OpenSSH user certificates, and a forced session wrapper so
sshfling: temporary SSH sessions are capped by a server-side wall-clock timeout.
sshfling:
sshfling: Homepage: https://grwlx.github.io/sshfling/
sshfling:
sshfling:
sshfling:
sshfling:
SLACKDESC

cat >"$public_dir/slackware/slack-required" <<'SLACKREQUIRED'
bash
jq
openssh
openssl
procps-ng
python3
shadow
util-linux
SLACKREQUIRED

cat >"$public_dir/opensuse/sshfling.spec" <<SPEC
Name:           sshfling
Version:        ${version}
Release:        1%{?dist}
Summary:        Temporary SSH access broker and CLI
License:        LicenseRef-SSHFling-Commercial
URL:            ${base_url}
Source0:        ${base_url}/downloads/${source_tar}
BuildArch:      noarch
Requires:       python3
Requires:       bash
Requires:       openssh
Requires:       openssl
Requires:       shadow
Requires:       procps
Requires:       util-linux
Requires:       jq

%description
SSHFling grants short-lived SSH access with default password grants, optional
OpenSSH user certificates, and a forced session wrapper so temporary SSH
sessions are capped by a server-side wall-clock timeout.

%prep
%autosetup

%build

%install
install -Dm755 bin/sshfling %{buildroot}%{_bindir}/sshfling
install -Dm755 native/sshfling-linux-account %{buildroot}%{_libexecdir}/sshfling/sshfling-linux-account
install -Dm755 native/sshfling-unix-identity %{buildroot}%{_libexecdir}/sshfling/sshfling-unix-identity
install -Dm755 production/sshfling-session %{buildroot}%{_datadir}/sshfling/templates/production/sshfling-session
install -Dm644 packaging/policy.json %{buildroot}%{_sysconfdir}/sshfling/policy.json
install -Dm644 LICENSE %{buildroot}%{_licensedir}/%{name}/LICENSE
install -Dm644 README.md %{buildroot}%{_docdir}/%{name}/README.md
mkdir -p %{buildroot}%{_datadir}/sshfling/templates
cp -a .env.example LICENSE README.md compose.server.yml compose.client.yml native scripts secrets ssh-client ssh-server production systemd %{buildroot}%{_datadir}/sshfling/templates/

%files
%{_bindir}/sshfling
%{_libexecdir}/sshfling/sshfling-linux-account
%{_libexecdir}/sshfling/sshfling-unix-identity
%config(missingok,noreplace) %{_sysconfdir}/sshfling/policy.json
%{_datadir}/sshfling/templates
%license %{_licensedir}/%{name}/LICENSE
%doc %{_docdir}/%{name}/README.md

%changelog
* Sat Jul 04 2026 ${maintainer} - ${version}-1
- Package sshfling for openSUSE Build Service
SPEC

cat >"$public_dir/snap/snapcraft.yaml" <<SNAP
name: sshfling
base: core24
version: '${version}'
summary: Temporary SSH access broker and CLI
description: |
  SSHFling grants short-lived SSH access with default password grants, optional
  OpenSSH user certificates, and a forced session wrapper so temporary SSH
  sessions are capped by a server-side wall-clock timeout.
license: Proprietary
grade: stable
confinement: classic

apps:
  sshfling:
    command: bin/sshfling
    environment:
      SSHFLING_TEMPLATE_DIR: \$SNAP/share/sshfling/templates
      SSHFLING_LINUX_ACCOUNT_HELPER: \$SNAP/share/sshfling/templates/native/sshfling-linux-account
      SSHFLING_UNIX_IDENTITY_HELPER: \$SNAP/share/sshfling/templates/native/sshfling-unix-identity

parts:
  sshfling:
    plugin: dump
    source: ${base_url}/downloads/${source_tar}
    organize:
      bin/sshfling: bin/sshfling
      native: share/sshfling/templates/native
      .env.example: share/sshfling/templates/.env.example
      LICENSE: share/sshfling/templates/LICENSE
      README.md: share/sshfling/templates/README.md
      compose.server.yml: share/sshfling/templates/compose.server.yml
      compose.client.yml: share/sshfling/templates/compose.client.yml
      scripts: share/sshfling/templates/scripts
      secrets: share/sshfling/templates/secrets
      ssh-client: share/sshfling/templates/ssh-client
      ssh-server: share/sshfling/templates/ssh-server
      production: share/sshfling/templates/production
      systemd: share/sshfling/templates/systemd
    stage-packages:
      - bash
      - jq
      - openssl
      - python3
      - openssh-client
      - passwd
      - procps
      - util-linux
SNAP

cat >"$public_dir/termux/packages/sshfling/build.sh" <<TERMUX
TERMUX_PKG_HOMEPAGE=${base_url}
TERMUX_PKG_DESCRIPTION="Temporary SSH access broker and CLI"
TERMUX_PKG_LICENSE="LicenseRef-SSHFling-Commercial"
TERMUX_PKG_MAINTAINER="${maintainer}"
TERMUX_PKG_VERSION=${version}
TERMUX_PKG_SRCURL=${base_url}/downloads/${source_tar}
TERMUX_PKG_SHA256=${source_sha}
TERMUX_PKG_DEPENDS="python, openssh, jq, procps, util-linux"
TERMUX_PKG_PLATFORM_INDEPENDENT=true

termux_step_make_install() {
	install -Dm755 bin/sshfling "\$TERMUX_PREFIX/bin/sshfling"
	install -Dm755 production/sshfling-session "\$TERMUX_PREFIX/share/sshfling/templates/production/sshfling-session"
	install -Dm644 LICENSE "\$TERMUX_PREFIX/share/doc/sshfling/LICENSE"
	install -Dm644 README.md "\$TERMUX_PREFIX/share/doc/sshfling/README.md"
	install -Dm644 packaging/policy.json "\$TERMUX_PREFIX/etc/sshfling/policy.json"
	mkdir -p "\$TERMUX_PREFIX/share/sshfling/templates"
	cp -a .env.example LICENSE README.md compose.server.yml compose.client.yml native scripts secrets ssh-client ssh-server production systemd "\$TERMUX_PREFIX/share/sshfling/templates/"
}
TERMUX

cat >"$public_dir/appimage/AppImageBuilder.yml" <<APPIMAGE
version: 1
script:
  - mkdir -p AppDir/usr/bin AppDir/usr/libexec/sshfling AppDir/usr/share/sshfling/templates
  - cp bin/sshfling AppDir/usr/bin/sshfling
  - cp native/sshfling-linux-account AppDir/usr/libexec/sshfling/sshfling-linux-account
  - cp native/sshfling-unix-identity AppDir/usr/libexec/sshfling/sshfling-unix-identity
  - cp -a .env.example LICENSE README.md compose.server.yml compose.client.yml native scripts secrets ssh-client ssh-server production systemd AppDir/usr/share/sshfling/templates/
  - chmod 0755 AppDir/usr/bin/sshfling AppDir/usr/libexec/sshfling/sshfling-linux-account AppDir/usr/libexec/sshfling/sshfling-unix-identity
  - install -Dm755 AppDir/usr/bin/sshfling AppDir/AppRun
AppDir:
  path: ./AppDir
  app_info:
    id: io.github.grwlx.sshfling
    name: SSHFling
    icon: utilities-terminal
    version: ${version}
    exec: usr/bin/sshfling
    exec_args: "\$@"
  apt:
    arch: amd64
    sources:
      - sourceline: deb https://archive.ubuntu.com/ubuntu/ noble main universe
    include:
      - bash
      - jq
      - openssl
      - python3
      - openssh-client
      - passwd
      - procps
      - util-linux
  files:
    include:
      - /usr/bin/python3*
      - /usr/bin/jq
      - /usr/bin/openssl
      - /usr/bin/ssh*
      - /usr/bin/getent
      - /usr/sbin/chpasswd
      - /usr/sbin/useradd
      - /usr/sbin/userdel
      - /usr/sbin/usermod
      - /usr/sbin/chage
      - /usr/bin/ps
      - /usr/bin/flock
      - /usr/lib/python3*
    exclude: []
APPIMAGE

if [[ -n "$windows_zip_name" ]]; then
  cat >"$public_dir/scoop/sshfling.json" <<SCOOP
{
  "version": "${version}",
  "description": "Temporary SSH access broker and CLI",
  "homepage": "${base_url}",
  "license": {
    "identifier": "Proprietary",
    "url": "https://github.com/${repository}/blob/main/LICENSE"
  },
  "url": "${base_url}/downloads/${windows_zip_name}",
  "hash": "${windows_zip_sha}",
  "bin": "sshfling.cmd",
  "checkver": {
    "github": "https://github.com/${repository}"
  },
  "autoupdate": {
    "url": "${base_url}/downloads/sshfling-\$version-windows.zip"
  }
}
SCOOP
fi

if [[ -n "$msi_name" ]]; then
  winget_dir="$public_dir/winget/manifests/g/${owner}/SSHFling/${version}"
  cat >"$winget_dir/${owner}.SSHFling.yaml" <<WINGET
PackageIdentifier: ${owner}.SSHFling
PackageVersion: ${version}
DefaultLocale: en-US
ManifestType: version
ManifestVersion: 1.9.0
WINGET

  cat >"$winget_dir/${owner}.SSHFling.locale.en-US.yaml" <<WINGET
PackageIdentifier: ${owner}.SSHFling
PackageVersion: ${version}
PackageLocale: en-US
Publisher: ${owner}
PackageName: SSHFling
License: SSHFling Commercial License
ShortDescription: Temporary SSH access broker and CLI
PackageUrl: https://github.com/${repository}
LicenseUrl: https://github.com/${repository}/blob/main/LICENSE
ManifestType: defaultLocale
ManifestVersion: 1.9.0
WINGET

  cat >"$winget_dir/${owner}.SSHFling.installer.yaml" <<WINGET
PackageIdentifier: ${owner}.SSHFling
PackageVersion: ${version}
InstallerType: wix
Scope: machine
UpgradeBehavior: install
ReleaseDate: $(date -u +%Y-%m-%d)
Installers:
  - Architecture: x64
    InstallerUrl: ${release_url}/${msi_name}
    InstallerSha256: ${msi_sha_upper}
ManifestType: installer
ManifestVersion: 1.9.0
WINGET

  cat >"$winget_dir/index.html" <<WINGET_INDEX
<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>SSHFling winget ${version}</title></head>
<body>
  <h1>SSHFling winget ${version}</h1>
  <ul>
    <li><a href="${owner}.SSHFling.yaml">${owner}.SSHFling.yaml</a></li>
    <li><a href="${owner}.SSHFling.locale.en-US.yaml">${owner}.SSHFling.locale.en-US.yaml</a></li>
    <li><a href="${owner}.SSHFling.installer.yaml">${owner}.SSHFling.installer.yaml</a></li>
  </ul>
</body>
</html>
WINGET_INDEX

  cat >"$public_dir/chocolatey/sshfling.nuspec" <<NUSPEC
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://schemas.microsoft.com/packaging/2015/06/nuspec.xsd">
  <metadata>
    <id>sshfling</id>
    <version>${version}</version>
    <title>SSHFling</title>
    <authors>${owner}</authors>
    <owners>${owner}</owners>
    <licenseUrl>https://github.com/${repository}/blob/main/LICENSE</licenseUrl>
    <projectUrl>https://github.com/${repository}</projectUrl>
    <packageSourceUrl>https://github.com/${repository}</packageSourceUrl>
    <requireLicenseAcceptance>true</requireLicenseAcceptance>
    <description>Temporary SSH access broker and CLI.</description>
    <summary>Temporary SSH access broker and CLI.</summary>
    <tags>ssh openssh certificate temporary-access cli</tags>
  </metadata>
  <files>
    <file src="tools\\**" target="tools" />
  </files>
</package>
NUSPEC

  cat >"$public_dir/chocolatey/tools/chocolateyinstall.ps1" <<CHOCO
\$ErrorActionPreference = 'Stop'

\$packageArgs = @{
  packageName    = 'sshfling'
  fileType       = 'msi'
  url64bit       = '${base_url}/downloads/${msi_name}'
  checksum64     = '${msi_sha}'
  checksumType64 = 'sha256'
  silentArgs     = '/qn /norestart'
  validExitCodes = @(0, 3010, 1641)
}

Install-ChocolateyPackage @packageArgs
CHOCO

  python3 - "$public_dir/chocolatey" "$public_dir/chocolatey/sshfling.${version}.nupkg" <<'PY'
import sys
import zipfile
from pathlib import Path

root = Path(sys.argv[1])
output = Path(sys.argv[2])
with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
    for relative in ["sshfling.nuspec", "tools/chocolateyinstall.ps1"]:
        archive.write(root / relative, relative)
PY

  choco_pkg_sha="$(hash_file sha256 "$public_dir/chocolatey/sshfling.${version}.nupkg")"
  cat >"$public_dir/chocolatey/install.ps1" <<CHOCO
\$ErrorActionPreference = "Stop"
\$tmp = Join-Path \$env:TEMP "sshfling-chocolatey"
New-Item -ItemType Directory -Force -Path \$tmp | Out-Null
\$pkg = Join-Path \$tmp "sshfling.${version}.nupkg"
Invoke-WebRequest -Uri "${base_url}/chocolatey/sshfling.${version}.nupkg" -OutFile \$pkg
\$expectedSha256 = "${choco_pkg_sha}"
\$actualSha256 = (Get-FileHash -Algorithm SHA256 -Path \$pkg).Hash.ToLowerInvariant()
if (\$actualSha256 -ne \$expectedSha256) {
  throw "SHA-256 mismatch for sshfling.${version}.nupkg"
}
choco install sshfling --source \$tmp -y
CHOCO
fi

cat >"$public_dir/community.html" <<HTML
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>SSHFling ${version} community package manifests</title>
  <style>
    body { font-family: system-ui, sans-serif; max-width: 960px; margin: 40px auto; padding: 0 20px; line-height: 1.5; }
    code, pre { background: #f4f4f5; border-radius: 6px; }
    code { padding: 2px 5px; }
    pre { padding: 14px; overflow-x: auto; }
    li { margin: 8px 0; }
  </style>
</head>
<body>
  <h1>SSHFling ${version} community package manifests</h1>
  <p>SSHFling is proprietary commercial software. Installing, running, redistributing, or submitting these manifests to third-party repositories requires the rights described in the project LICENSE or a separate written agreement from GRWLX.</p>
  <p>These files are generated from the release artifacts. Some ecosystems can install directly from these URLs; official/community repositories such as AUR, FreeBSD Ports, pkgsrc, winget, Chocolatey, Snapcraft, and distro repos still require maintainer account submission and review.</p>
  <p>Dependency ownership remains with the target operating system, package manager, base image, or fleet policy. The manifests declare Python, OpenSSH, account-management, process, and util-linux capabilities where each ecosystem supports that metadata, but package uninstall should not remove or downgrade those shared dependencies or revert host SSH configuration.</p>
  <p>Trust model: review the generated manifest, verify the embedded release checksums or package hashes, and use the ecosystem's normal signed repository or maintainer-submission flow before fleet deployment. The generated helpers do not use insecure package-manager bypass flags.</p>
  <ul>
    <li>Arch / AUR: <a href="arch/PKGBUILD">PKGBUILD</a>, <a href="arch/.SRCINFO">.SRCINFO</a></li>
    <li>Alpine: <a href="alpine/APKBUILD">APKBUILD</a></li>
    <li>FreeBSD Ports: <a href="freebsd/security/sshfling/Makefile">security/sshfling port</a></li>
    <li>OpenBSD Ports: <a href="openbsd/security/sshfling/Makefile">security/sshfling port</a></li>
    <li>pkgsrc for NetBSD, DragonFly BSD, illumos, and SmartOS: <a href="pkgsrc/security/sshfling/Makefile">security/sshfling package</a></li>
    <li>Nix: <a href="nix/flake.nix">flake.nix</a></li>
    <li>Guix: <a href="guix/sshfling.scm">sshfling.scm</a></li>
    <li>Void Linux: <a href="void/template">xbps-src template</a></li>
    <li>Gentoo: <a href="gentoo/app-admin/sshfling/sshfling-${version}.ebuild">ebuild</a></li>
    <li>Slackware: <a href="slackware/sshfling.SlackBuild">SlackBuild</a>, <a href="slackware/slack-desc">slack-desc</a>, <a href="slackware/slack-required">slack-required</a></li>
    <li>openSUSE OBS: <a href="opensuse/sshfling.spec">spec file</a></li>
    <li>Snapcraft: <a href="snap/snapcraft.yaml">snapcraft.yaml</a></li>
    <li>Termux: <a href="termux/packages/sshfling/build.sh">package build.sh</a></li>
    <li>AppImage: <a href="appimage/AppImageBuilder.yml">AppImageBuilder.yml</a></li>
    <li>Scoop: <a href="scoop/sshfling.json">manifest</a></li>
    <li>winget: <a href="winget/manifests/g/${owner}/SSHFling/${version}/">multi-file manifest directory</a></li>
    <li>Chocolatey: <a href="chocolatey/sshfling.${version}.nupkg">nupkg</a>, <a href="chocolatey/sshfling.nuspec">nuspec</a></li>
  </ul>
  <h2>Fast Commands</h2>
  <pre><code>curl -fsSLO ${base_url}/arch/PKGBUILD &amp;&amp; makepkg -si
scoop install ${base_url}/scoop/sshfling.json
\$chocoInstaller = Join-Path \$env:TEMP "sshfling-chocolatey-install.ps1"
Invoke-WebRequest -Uri "${base_url}/chocolatey/install.ps1" -OutFile \$chocoInstaller
&amp; \$chocoInstaller</code></pre>
</body>
</html>
HTML
