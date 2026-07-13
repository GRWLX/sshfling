Name:           sshfling
Version:        0.1.21
Release:        1%{?dist}
Summary:        Temporary SSH access broker and CLI

%{!?_unitdir:%global _unitdir %{_prefix}/lib/systemd/system}
%{!?systemd_post:%global systemd_post() %{nil}}
%{!?systemd_preun:%global systemd_preun() %{nil}}
%{!?systemd_postun:%global systemd_postun() %{nil}}
%{!?systemd_postun_with_restart:%global systemd_postun_with_restart() %{nil}}

License:        LicenseRef-SSHFling-Commercial
URL:            https://github.com/GRWLX/sshfling
Source0:        %{url}/archive/refs/tags/v%{version}/%{name}-%{version}.tar.gz

BuildArch:      noarch
BuildRequires:  bash
BuildRequires:  systemd-rpm-macros
Requires:       bash
Requires:       jq
Requires:       openssh-clients
Requires:       openssl
Requires:       procps-ng
Requires:       python3
Requires:       shadow-utils
Requires(pre):  shadow-utils
Requires:       util-linux
Recommends:     openssh-server
Recommends:     rsync

%description
SSHFling grants short-lived SSH access with default password grants, optional
OpenSSH user certificates, and a forced session wrapper so temporary SSH
sessions are capped by a server-side wall-clock timeout. Docker Compose files
are included as a test harness.

This draft Fedora spec is not ready for official Fedora or EPEL review while
the upstream license remains proprietary and redistribution-restricted.

%prep
%autosetup

%build

%install
install -d %{buildroot}%{_bindir}
install -d %{buildroot}%{_sysconfdir}/sshfling
install -d %{buildroot}%{_libexecdir}/sshfling
install -d %{buildroot}%{_unitdir}
install -d %{buildroot}%{_docdir}/%{name}
install -d %{buildroot}%{_mandir}/man1
install -d %{buildroot}%{_datadir}/sshfling/templates

install -m 0755 bin/sshfling %{buildroot}%{_bindir}/sshfling
install -m 0755 native/sshfling-linux-account %{buildroot}%{_libexecdir}/sshfling/sshfling-linux-account
install -m 0755 native/sshfling-unix-identity %{buildroot}%{_libexecdir}/sshfling/sshfling-unix-identity
install -m 0644 packaging/policy.json %{buildroot}%{_sysconfdir}/sshfling/policy.json
install -m 0640 systemd/sshflingd.env.example %{buildroot}%{_sysconfdir}/sshfling/sshflingd.env
bash -c 'source packaging/copy-templates.sh; copy_sshfling_templates "$PWD" %{buildroot}%{_datadir}/sshfling/templates'
install -m 0644 systemd/sshflingd.service %{buildroot}%{_unitdir}/sshflingd.service
install -m 0644 systemd/sshfling-prune.service %{buildroot}%{_unitdir}/sshfling-prune.service
install -m 0644 systemd/sshfling-prune.timer %{buildroot}%{_unitdir}/sshfling-prune.timer
install -m 0644 debian/sshfling.1 %{buildroot}%{_mandir}/man1/sshfling.1

sed -i '1s|^#!/usr/bin/env python3$|#!/usr/bin/python3|' %{buildroot}%{_bindir}/sshfling
find %{buildroot}%{_datadir}/sshfling/templates -type f -perm /111 \
  -exec sed -i '1s|^#!/usr/bin/env bash$|#!/usr/bin/bash|' {} +

%pre
getent group sshflingd >/dev/null || groupadd -r sshflingd
getent passwd sshflingd >/dev/null || \
  useradd -r -g sshflingd -d /var/lib/sshflingd -s /usr/sbin/nologin -M sshflingd

%post
install -d -m 0750 -o root -g sshflingd %{_sysconfdir}/sshfling
install -d -m 0750 -o sshflingd -g sshflingd /var/lib/sshflingd
if [ -f %{_sysconfdir}/sshfling/sshflingd.env ] && [ ! -L %{_sysconfdir}/sshfling/sshflingd.env ]; then
  chown root:sshflingd %{_sysconfdir}/sshfling/sshflingd.env
  chmod 0640 %{_sysconfdir}/sshfling/sshflingd.env
fi
%systemd_post sshflingd.service sshfling-prune.timer

%preun
%systemd_preun sshflingd.service sshfling-prune.timer

%postun
%systemd_postun_with_restart sshflingd.service
%systemd_postun sshfling-prune.timer

%files
%license LICENSE
%doc README.md
%doc systemd/sshflingd.env.example
%dir %attr(0750,root,sshflingd) %{_sysconfdir}/sshfling
%config(noreplace) %{_sysconfdir}/sshfling/policy.json
%config(noreplace) %attr(0640,root,sshflingd) %{_sysconfdir}/sshfling/sshflingd.env
%{_bindir}/sshfling
%{_mandir}/man1/sshfling.1*
%dir %{_libexecdir}/sshfling
%{_libexecdir}/sshfling/sshfling-linux-account
%{_libexecdir}/sshfling/sshfling-unix-identity
%{_unitdir}/sshflingd.service
%{_unitdir}/sshfling-prune.service
%{_unitdir}/sshfling-prune.timer
%{_datadir}/sshfling

%changelog
* Mon Jul 13 2026 SSHFling Maintainers <root@localhost> - 0.1.21-1
- Initial draft Fedora spec; not ready for review until the license gate is resolved.
