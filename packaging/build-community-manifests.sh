#!/usr/bin/env bash
set -euo pipefail

package_dist="${1:?package dist directory is required}"
public_dir="${2:?public directory is required}"
base_url="${3:?base URL is required}"
version="${4:?version is required}"
repository="${5:?repository is required}"

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
    value = int.from_bytes(raw, "big")
    length = (len(raw) * 8 + 4) // 5
    chars = []
    for index in range(length - 1, -1, -1):
        chars.append(alphabet[(value >> (index * 5)) & 31])
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
pkgdesc="Temporary SSH certificate issuer and access CLI"
arch=('any')
url="${base_url}"
license=('Apache-2.0')
depends=('python' 'openssh' 'shadow' 'procps-ng' 'util-linux')
optdepends=('docker: Docker Compose test harness')
backup=('etc/sshfling/policy.json')
source=("\${pkgname}-\${pkgver}.tar.gz::${base_url}/downloads/${source_tar}")
sha256sums=('${source_sha}')

package() {
  cd "\${srcdir}/\${pkgname}-\${pkgver}"
  install -Dm755 bin/sshfling "\${pkgdir}/usr/bin/sshfling"
  install -Dm755 production/sshfling-session "\${pkgdir}/usr/share/sshfling/templates/production/sshfling-session"
  install -Dm644 packaging/policy.json "\${pkgdir}/etc/sshfling/policy.json"
  install -Dm644 systemd/sshflingd.service "\${pkgdir}/usr/lib/systemd/system/sshflingd.service"
  install -Dm644 systemd/sshflingd.env.example "\${pkgdir}/usr/share/doc/sshfling/sshflingd.env.example"
  install -Dm644 LICENSE "\${pkgdir}/usr/share/licenses/sshfling/LICENSE"
  install -Dm644 README.md "\${pkgdir}/usr/share/doc/sshfling/README.md"
  install -d "\${pkgdir}/usr/share/sshfling/templates"
  cp -a .env.example LICENSE README.md compose.server.yml compose.client.yml scripts secrets ssh-client ssh-server production systemd "\${pkgdir}/usr/share/sshfling/templates/"
}
PKGBUILD

cat >"$public_dir/arch/.SRCINFO" <<SRCINFO
pkgbase = sshfling
	pkgdesc = Temporary SSH certificate issuer and access CLI
	pkgver = ${version}
	pkgrel = 1
	url = ${base_url}
	arch = any
	license = Apache-2.0
	depends = python
	depends = openssh
	depends = shadow
	depends = procps-ng
	depends = util-linux
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
pkgdesc="Temporary SSH certificate issuer and access CLI"
url="${base_url}"
arch="noarch"
license="Apache-2.0"
depends="python3 openssh-client shadow procps util-linux"
options="!check"
source="\$pkgname-\$pkgver.tar.gz::${base_url}/downloads/${source_tar}"
builddir="\$srcdir/\$pkgname-\$pkgver"

package() {
	install -Dm755 "\$builddir/bin/sshfling" "\$pkgdir/usr/bin/sshfling"
	install -Dm755 "\$builddir/production/sshfling-session" "\$pkgdir/usr/share/sshfling/templates/production/sshfling-session"
	install -Dm644 "\$builddir/packaging/policy.json" "\$pkgdir/etc/sshfling/policy.json"
	install -Dm644 "\$builddir/LICENSE" "\$pkgdir/usr/share/licenses/sshfling/LICENSE"
	install -Dm644 "\$builddir/README.md" "\$pkgdir/usr/share/doc/sshfling/README.md"
	mkdir -p "\$pkgdir/usr/share/sshfling/templates"
	cp -a "\$builddir"/.env.example "\$builddir"/LICENSE "\$builddir"/README.md "\$builddir"/compose.server.yml "\$builddir"/compose.client.yml \
		"\$builddir"/scripts "\$builddir"/secrets "\$builddir"/ssh-client "\$builddir"/ssh-server "\$builddir"/production "\$builddir"/systemd \
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
COMMENT=	Temporary SSH certificate issuer and access CLI
WWW=		${base_url}

LICENSE=	APACHE20

RUN_DEPENDS=	python3:lang/python3

USES=		python shebangfix
SHEBANG_FILES=	bin/sshfling
NO_BUILD=	yes

do-install:
	\${INSTALL_SCRIPT} \${WRKSRC}/bin/sshfling \${STAGEDIR}\${PREFIX}/bin/sshfling
	\${INSTALL_SCRIPT} \${WRKSRC}/production/sshfling-session \${STAGEDIR}\${PREFIX}/libexec/sshfling-session
	\${MKDIR} \${STAGEDIR}\${PREFIX}/etc/sshfling
	\${INSTALL_DATA} \${WRKSRC}/packaging/policy.json \${STAGEDIR}\${PREFIX}/etc/sshfling/policy.json.sample
	\${MKDIR} \${STAGEDIR}\${DOCSDIR}
	\${INSTALL_DATA} \${WRKSRC}/README.md \${WRKSRC}/LICENSE \${STAGEDIR}\${DOCSDIR}/

.include <bsd.port.mk>
MAKEFILE

cat >"$public_dir/freebsd/security/sshfling/distinfo" <<DISTINFO
TIMESTAMP = $(date -u +%s)
SHA256 (${source_tar}) = ${source_sha}
SIZE (${source_tar}) = ${source_size}
DISTINFO

cat >"$public_dir/freebsd/security/sshfling/pkg-descr" <<PKGDESCR
SSHFling issues short-lived OpenSSH user certificates and installs a forced
session wrapper so temporary SSH sessions are capped by a server-side
wall-clock timeout.
PKGDESCR

cat >"$public_dir/freebsd/security/sshfling/pkg-plist" <<PLIST
bin/sshfling
libexec/sshfling-session
@sample etc/sshfling/policy.json.sample
%%DOCSDIR%%/LICENSE
%%DOCSDIR%%/README.md
PLIST

openbsd_sha="$(openssl dgst -sha256 -binary "$source_path" | base64 | tr -d '\n')"
cat >"$public_dir/openbsd/security/sshfling/Makefile" <<MAKEFILE
COMMENT =	temporary SSH certificate issuer and access CLI
DISTNAME =	sshfling-${version}
CATEGORIES =	security sysutils

HOMEPAGE =	${base_url}
MAINTAINER =	${maintainer}

# Apache-2.0
PERMIT_PACKAGE =	Yes

MASTER_SITES =	${base_url}/downloads/

MODULES =	lang/python
NO_BUILD =	Yes

do-install:
	\${INSTALL_SCRIPT} \${WRKSRC}/bin/sshfling \${PREFIX}/bin/sshfling
	\${INSTALL_SCRIPT} \${WRKSRC}/production/sshfling-session \${PREFIX}/libexec/sshfling-session
	\${INSTALL_DATA_DIR} \${PREFIX}/share/doc/sshfling
	\${INSTALL_DATA} \${WRKSRC}/README.md \${WRKSRC}/LICENSE \${PREFIX}/share/doc/sshfling/
	\${INSTALL_DATA_DIR} \${SYSCONFDIR}/sshfling
	\${INSTALL_DATA} \${WRKSRC}/packaging/policy.json \${SYSCONFDIR}/sshfling/policy.json

.include <bsd.port.mk>
MAKEFILE

cat >"$public_dir/openbsd/security/sshfling/distinfo" <<DISTINFO
SHA256 (${source_tar}) = ${openbsd_sha}
SIZE (${source_tar}) = ${source_size}
DISTINFO

cat >"$public_dir/openbsd/security/sshfling/pkg/DESCR" <<DESCR
SSHFling issues short-lived OpenSSH user certificates and installs a forced
session wrapper so temporary SSH sessions are capped by a server-side
wall-clock timeout.
DESCR

cat >"$public_dir/openbsd/security/sshfling/pkg/PLIST" <<PLIST
@bin bin/sshfling
libexec/sshfling-session
@sample \${SYSCONFDIR}/sshfling/policy.json
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
COMMENT=	Temporary SSH certificate issuer and access CLI
LICENSE=	apache-2.0

USE_LANGUAGES=	# none
NO_BUILD=	yes
REPLACE_PYTHON=	bin/sshfling
INSTALLATION_DIRS=	bin libexec share/doc/sshfling etc/sshfling

do-install:
	\${INSTALL_SCRIPT} \${WRKSRC}/bin/sshfling \${DESTDIR}\${PREFIX}/bin/sshfling
	\${INSTALL_SCRIPT} \${WRKSRC}/production/sshfling-session \${DESTDIR}\${PREFIX}/libexec/sshfling-session
	\${INSTALL_DATA} \${WRKSRC}/README.md \${DESTDIR}\${PREFIX}/share/doc/sshfling/README.md
	\${INSTALL_DATA} \${WRKSRC}/LICENSE \${DESTDIR}\${PREFIX}/share/doc/sshfling/LICENSE
	\${INSTALL_DATA} \${WRKSRC}/packaging/policy.json \${DESTDIR}\${PREFIX}/etc/sshfling/policy.json

.include "../../lang/python/application.mk"
.include "../../mk/bsd.pkg.mk"
MAKEFILE

cat >"$public_dir/pkgsrc/security/sshfling/DESCR" <<DESCR
SSHFling issues short-lived OpenSSH user certificates and installs a forced
session wrapper so temporary SSH sessions are capped by a server-side
wall-clock timeout.
DESCR

cat >"$public_dir/pkgsrc/security/sshfling/PLIST" <<PLIST
@comment \$NetBSD\$
bin/sshfling
libexec/sshfling-session
share/doc/sshfling/LICENSE
share/doc/sshfling/README.md
etc/sshfling/policy.json
PLIST

cat >"$public_dir/pkgsrc/security/sshfling/distinfo" <<DISTINFO
\$NetBSD\$

BLAKE2s (${source_tar}) = ${source_blake2s}
SHA512 (${source_tar}) = ${source_sha512}
Size (${source_tar}) = ${source_size} bytes
DISTINFO

cat >"$public_dir/nix/flake.nix" <<NIX
{
  description = "SSHFling temporary SSH certificate issuer and access CLI";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          runtimePath = [ pkgs.python3 pkgs.openssh pkgs.procps pkgs.util-linux ] ++ pkgs.lib.optionals pkgs.stdenv.isLinux [ pkgs.shadow ];
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
              install -Dm755 production/sshfling-session \$out/share/sshfling/templates/production/sshfling-session
              install -Dm644 LICENSE \$out/share/doc/sshfling/LICENSE
              install -Dm644 README.md \$out/share/doc/sshfling/README.md
              mkdir -p \$out/share/sshfling/templates
              cp -a .env.example LICENSE README.md compose.server.yml compose.client.yml scripts secrets ssh-client ssh-server production systemd \$out/share/sshfling/templates/
              patchShebangs \$out/bin/sshfling
              wrapProgram \$out/bin/sshfling --prefix PATH : \${pkgs.lib.makeBinPath runtimePath}
              runHook postInstall
            '';
            meta = with pkgs.lib; {
              description = "Temporary SSH certificate issuer and access CLI";
              homepage = "${base_url}";
              license = licenses.asl20;
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
  #:use-module (gnu packages linux)
  #:use-module (gnu packages python)
  #:use-module (gnu packages ssh))

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
         ("production/sshfling-session" "share/sshfling/templates/production/sshfling-session")
         ("README.md" "share/doc/sshfling/README.md")
         ("LICENSE" "share/doc/sshfling/LICENSE")
         ("packaging/policy.json" "etc/sshfling/policy.json"))))
    (inputs (list python openssh shadow procps util-linux))
    (home-page "${base_url}")
    (synopsis "Temporary SSH certificate issuer and access CLI")
    (description
     "SSHFling issues short-lived OpenSSH user certificates and installs a forced session wrapper so temporary SSH sessions are capped by a server-side wall-clock timeout.")
    (license license:asl2.0)))
GUIX

cat >"$public_dir/void/template" <<VOID
# Template file for 'sshfling'
pkgname=sshfling
version=${version}
revision=1
depends="python3 openssh shadow procps-ng util-linux"
short_desc="Temporary SSH certificate issuer and access CLI"
maintainer="${maintainer}"
license="Apache-2.0"
homepage="${base_url}"
distfiles="${base_url}/downloads/${source_tar}"
checksum=${source_sha}

do_install() {
	vbin bin/sshfling
	vinstall production/sshfling-session 755 usr/share/sshfling/templates/production
	vinstall packaging/policy.json 644 etc/sshfling
	vlicense LICENSE
	vdoc README.md
	vmkdir usr/share/sshfling/templates
	vcopy ".env.example LICENSE README.md compose.server.yml compose.client.yml scripts secrets ssh-client ssh-server production systemd" usr/share/sshfling/templates
}
VOID

cat >"$public_dir/gentoo/app-admin/sshfling/sshfling-${version}.ebuild" <<GENTOO
EAPI=8

inherit python-r1 systemd

DESCRIPTION="Temporary SSH certificate issuer and access CLI"
HOMEPAGE="${base_url}"
SRC_URI="${base_url}/downloads/${source_tar}"

LICENSE="Apache-2.0"
SLOT="0"
KEYWORDS="~amd64 ~arm64"
REQUIRED_USE="\${PYTHON_REQUIRED_USE}"
RDEPEND="\${PYTHON_DEPS}
	virtual/ssh
	sys-apps/shadow
	sys-process/procps
	sys-apps/util-linux"

src_install() {
	python_fix_shebang bin/sshfling
	dobin bin/sshfling
	exeinto /usr/share/sshfling/templates/production
	doexe production/sshfling-session
	insinto /etc/sshfling
	doins packaging/policy.json
	systemd_dounit systemd/sshflingd.service
	dodoc README.md
	newdoc LICENSE LICENSE
	insinto /usr/share/sshfling/templates
	doins .env.example LICENSE README.md compose.server.yml compose.client.yml
	doins -r scripts secrets ssh-client ssh-server production systemd
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
install -Dm755 production/sshfling-session "$PKG/usr/share/sshfling/templates/production/sshfling-session"
install -Dm644 packaging/policy.json "$PKG/etc/sshfling/policy.json"
install -Dm644 LICENSE "$PKG/usr/doc/$PRGNAM-$VERSION/LICENSE"
install -Dm644 README.md "$PKG/usr/doc/$PRGNAM-$VERSION/README.md"
mkdir -p "$PKG/usr/share/sshfling/templates"
cp -a .env.example LICENSE README.md compose.server.yml compose.client.yml scripts secrets ssh-client ssh-server production systemd "$PKG/usr/share/sshfling/templates/"
mkdir -p "$PKG/install"
cat "$CWD/slack-desc" > "$PKG/install/slack-desc"

cd "$PKG"
/sbin/makepkg -l y -c n "$OUTPUT/$PRGNAM-$VERSION-$ARCH-$BUILD$TAG.txz"
SLACKBUILD
sed -i "s/__VERSION__/${version}/g" "$public_dir/slackware/sshfling.SlackBuild"
chmod 0755 "$public_dir/slackware/sshfling.SlackBuild"

cat >"$public_dir/slackware/slack-desc" <<'SLACKDESC'
sshfling: sshfling (temporary SSH certificate issuer)
sshfling:
sshfling: SSHFling issues short-lived OpenSSH user certificates and installs
sshfling: a forced session wrapper so temporary SSH sessions are capped by a
sshfling: server-side wall-clock timeout.
sshfling:
sshfling: Homepage: https://grwlx.github.io/sshfling/
sshfling:
sshfling:
sshfling:
sshfling:
SLACKDESC

cat >"$public_dir/opensuse/sshfling.spec" <<SPEC
Name:           sshfling
Version:        ${version}
Release:        1%{?dist}
Summary:        Temporary SSH certificate issuer and access CLI
License:        Apache-2.0
URL:            ${base_url}
Source0:        ${base_url}/downloads/${source_tar}
BuildArch:      noarch
Requires:       python3
Requires:       openssh
Requires:       shadow
Requires:       procps
Requires:       util-linux

%description
SSHFling issues short-lived OpenSSH user certificates and installs a forced
session wrapper so temporary SSH sessions are capped by a server-side
wall-clock timeout.

%prep
%autosetup

%build

%install
install -Dm755 bin/sshfling %{buildroot}%{_bindir}/sshfling
install -Dm755 production/sshfling-session %{buildroot}%{_datadir}/sshfling/templates/production/sshfling-session
install -Dm644 packaging/policy.json %{buildroot}%{_sysconfdir}/sshfling/policy.json
install -Dm644 LICENSE %{buildroot}%{_licensedir}/%{name}/LICENSE
install -Dm644 README.md %{buildroot}%{_docdir}/%{name}/README.md

%files
%{_bindir}/sshfling
%config(noreplace) %{_sysconfdir}/sshfling/policy.json
%{_datadir}/sshfling/templates/production/sshfling-session
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
summary: Temporary SSH certificate issuer and access CLI
description: |
  SSHFling issues short-lived OpenSSH user certificates and installs a forced
  session wrapper so temporary SSH sessions are capped by a server-side
  wall-clock timeout.
license: Apache-2.0
grade: stable
confinement: classic

apps:
  sshfling:
    command: bin/sshfling

parts:
  sshfling:
    plugin: dump
    source: ${base_url}/downloads/${source_tar}
    organize:
      bin/sshfling: bin/sshfling
    stage-packages:
      - python3
      - openssh-client
      - passwd
      - procps
      - util-linux
SNAP

cat >"$public_dir/termux/packages/sshfling/build.sh" <<TERMUX
TERMUX_PKG_HOMEPAGE=${base_url}
TERMUX_PKG_DESCRIPTION="Temporary SSH certificate issuer and access CLI"
TERMUX_PKG_LICENSE="Apache-2.0"
TERMUX_PKG_MAINTAINER="${maintainer}"
TERMUX_PKG_VERSION=${version}
TERMUX_PKG_SRCURL=${base_url}/downloads/${source_tar}
TERMUX_PKG_SHA256=${source_sha}
TERMUX_PKG_DEPENDS="python, openssh, procps, util-linux"
TERMUX_PKG_PLATFORM_INDEPENDENT=true

termux_step_make_install() {
	install -Dm755 bin/sshfling "\$TERMUX_PREFIX/bin/sshfling"
	install -Dm755 production/sshfling-session "\$TERMUX_PREFIX/share/sshfling/templates/production/sshfling-session"
	install -Dm644 LICENSE "\$TERMUX_PREFIX/share/doc/sshfling/LICENSE"
	install -Dm644 README.md "\$TERMUX_PREFIX/share/doc/sshfling/README.md"
	install -Dm644 packaging/policy.json "\$TERMUX_PREFIX/etc/sshfling/policy.json"
}
TERMUX

cat >"$public_dir/appimage/AppImageBuilder.yml" <<APPIMAGE
version: 1
script:
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
      - sourceline: deb http://archive.ubuntu.com/ubuntu/ noble main universe
    include:
      - python3
      - openssh-client
      - passwd
      - procps
      - util-linux
  files:
    include:
      - /usr/bin/python3*
      - /usr/bin/ssh*
      - /usr/sbin/chpasswd
      - /usr/sbin/useradd
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
  "description": "Temporary SSH certificate issuer and access CLI",
  "homepage": "${base_url}",
  "license": "Apache-2.0",
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
License: Apache-2.0
ShortDescription: Temporary SSH certificate issuer and access CLI
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
    <requireLicenseAcceptance>false</requireLicenseAcceptance>
    <description>Temporary SSH certificate issuer and access CLI.</description>
    <summary>Temporary SSH certificate issuer and access CLI.</summary>
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

  cat >"$public_dir/chocolatey/install.ps1" <<CHOCO
\$ErrorActionPreference = "Stop"
\$tmp = Join-Path \$env:TEMP "sshfling-chocolatey"
New-Item -ItemType Directory -Force -Path \$tmp | Out-Null
\$pkg = Join-Path \$tmp "sshfling.${version}.nupkg"
Invoke-WebRequest -Uri "${base_url}/chocolatey/sshfling.${version}.nupkg" -OutFile \$pkg
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
  <p>These files are generated from the release artifacts. Some ecosystems can install directly from these URLs; official/community repositories such as AUR, FreeBSD Ports, pkgsrc, winget, Chocolatey, Snapcraft, and distro repos still require maintainer account submission and review.</p>
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
    <li>Slackware: <a href="slackware/sshfling.SlackBuild">SlackBuild</a>, <a href="slackware/slack-desc">slack-desc</a></li>
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
irm ${base_url}/chocolatey/install.ps1 | iex</code></pre>
</body>
</html>
HTML
