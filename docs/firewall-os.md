# Firewall OS Compatibility

SSHFling supports pfSense and OPNsense as FreeBSD-family firewall targets for
the portable client/runtime and certificate-mode host preparation path. The
Linux temporary password-user workflow is intentionally not treated as supported
on these firewall appliances because it requires Linux account-management tools
such as `useradd` and `chpasswd`.

This document cross-references vendor firewall releases to the FreeBSD
substrates we can validate in public GitHub Actions. These tests validate the
portable SSHFling runtime against matching FreeBSD bases, or matching
major/minor FreeBSD lines for vendor `CURRENT` builds; they do not claim to boot
vendor appliance images or exercise firewall GUI-managed configuration.

## CI Substrate Matrix

The `Cross OS validation` workflow includes firewall-focused FreeBSD jobs for
the pfSense and OPNsense substrates that public CI can boot:

| FreeBSD substrate | Firewall release coverage | CI status |
| --- | --- | --- |
| FreeBSD 12.4 | pfSense Plus 22.x, pfSense CE 2.6.x, and OPNsense HardenedBSD/FreeBSD 12.x-era releases | Historical mapping only; not active enterprise CI because the remaining public bootstrap archive is unsigned |
| FreeBSD 13.2 | OPNsense 23.x, OPNsense 24.1, and Business 24.4 | Matching FreeBSD VM coverage |
| FreeBSD 13.3 | no direct pfSense/OPNsense release mapping found | Public 13.x continuity smoke |
| FreeBSD 13.4 | no direct pfSense/OPNsense release mapping found | Public 13.x continuity smoke |
| FreeBSD 13.5 | no direct pfSense/OPNsense release mapping found | Public 13.x continuity smoke |
| FreeBSD 14.0 | pfSense CE 2.7.x and pfSense Plus 23.x | Major/minor VM coverage for the 14.0-CURRENT line |
| FreeBSD 14.1 | OPNsense 24.7 and Business 24.10 | Matching FreeBSD VM coverage |
| FreeBSD 14.2 | OPNsense 25.1 and Business 25.4 | Matching FreeBSD VM coverage |
| FreeBSD 14.3 | OPNsense 25.7, 26.1, Business 25.10, and Business 26.4 | Matching FreeBSD VM coverage |
| FreeBSD 14.4 | no direct pfSense/OPNsense release mapping found | Public 14.x continuity smoke |
| FreeBSD 15.0 | pfSense CE 2.8.x, pfSense Plus 24.x, and pfSense Plus 25.07 | Major/minor VM coverage for the 15.0-CURRENT line |
| FreeBSD 15.1 | OPNsense 26.7 tracking target | Tracking VM coverage |
| FreeBSD 16.0-CURRENT | pfSense Plus 25.11/26.x and planned pfSense CE 2.9.x | Public runner gap |
| FreeBSD 11.x and older | older unsupported pfSense and OPNsense lines | Not covered |

The tests install `sshfling` from the public source release, run the portable
CLI contract, and exercise `sshfling host install --dry-run --no-validate` with
certificate-mode paths. This validates command parsing, JSON output, password
hashing, SSH connect dry-run behavior, template initialization, and host
configuration rendering without modifying a firewall appliance.

The complete version index found in the vendor documentation is tracked in
[firewall-os-versions.md](firewall-os-versions.md).

## pfSense Cross-Reference

Netgate publishes a release table mapping pfSense software to FreeBSD versions.
The SSHFling CI mapping is:

| pfSense family | Vendor FreeBSD base | SSHFling validation |
| --- | --- | --- |
| pfSense Plus 26.07 / 26.03.x | 16.0-CURRENT | Not in public CI yet |
| pfSense Plus 25.11.x | 16.0-CURRENT | Not in public CI yet |
| pfSense Plus 25.07.x | 15.0-CURRENT | FreeBSD 15.0 VM |
| pfSense Plus 24.x | 15.0-CURRENT | FreeBSD 15.0 VM |
| pfSense Plus 23.x | 14.0-CURRENT | FreeBSD 14.0 VM |
| pfSense Plus 22.x | 12.3-STABLE | FreeBSD 12.4 nearest 12.x smoke, not exact |
| pfSense Plus 21.x | 12.2-STABLE | FreeBSD 12.4 nearest 12.x smoke, not exact |
| pfSense CE 2.9.x | 16.0-CURRENT planned | Not in public CI yet |
| pfSense CE 2.8.x | 15.0-CURRENT | FreeBSD 15.0 VM |
| pfSense CE 2.7.x | 14.0-CURRENT | FreeBSD 14.0 VM |
| pfSense CE 2.6.x | 12.3-STABLE | FreeBSD 12.4 nearest 12.x smoke, not exact |
| pfSense CE 2.5.x | 12.2-STABLE | FreeBSD 12.4 nearest 12.x smoke, not exact |
| pfSense CE 2.4.x and older | 11.x, 10.x, 8.x, 7.x, or 6.x | Not in public CI |

## OPNsense Cross-Reference

OPNsense release notes and release indexes map the current and recent release
families to FreeBSD bases. The SSHFling CI mapping is:

| OPNsense family | Vendor FreeBSD base | SSHFling validation |
| --- | --- | --- |
| Community 26.1 | 14.3 line, with 15.1 preparation noted for 26.7 | FreeBSD 14.3 VM plus 15.1 tracking VM |
| Business 26.4 | based on Community 26.1 | FreeBSD 14.3 VM plus 15.1 tracking VM |
| Community 25.7 | 14.3 | FreeBSD 14.3 VM |
| Business 25.10 | 14.3 | FreeBSD 14.3 VM |
| Community 25.1 | 14.2 | FreeBSD 14.2 VM |
| Business 25.4 | 14.2 | FreeBSD 14.2 VM |
| Community 24.7 | 14.1 | FreeBSD 14.1 VM |
| Business 24.10 | 14.1 | FreeBSD 14.1 VM |
| Community 24.1 / Business 24.4 | 13.2 | FreeBSD 13.2 VM |
| Community 23.x / Business 23.x | 13.x | FreeBSD 13.2 VM as nearest public 13.x coverage |
| Community/Business 22.x | 13.0 to 13.1 | FreeBSD 13.2 VM as nearest public 13.x coverage |
| Community/Business 20.x to 21.x | HardenedBSD/FreeBSD 12.x-era bases | FreeBSD 12.4 nearest 12.x smoke, not exact |
| Community/Business 19.x and older | 11.x, 10.x, or HardenedBSD-era bases | Not in public CI |

## Operational Boundary

Use SSHFling certificate mode with an existing pfSense or OPNsense user that is
already allowed to use SSH. Do not use `sudo sshfling -p` on pfSense or
OPNsense; password mode is Linux-only.

OPNsense documents a custom OpenSSH include directory at:

```text
/usr/local/etc/ssh/sshd_config.d/
```

pfSense SSH is managed from the firewall GUI. Netgate also warns that extra
FreeBSD packages or hand-managed files on pfSense require manual backup and may
be affected by firmware updates, so avoid treating pfSense like a general
purpose FreeBSD server.

Recommended firewall client use:

```sh
sshfling init ~/sshfling-firewall
sshfling --version
sshfling user@firewall.example
```

For server-side certificate configuration on a firewall, run host-install first
as a dry run and review the generated config paths:

```sh
sudo sshfling host install --dry-run --no-validate \
  --ca-pub /path/to/ca_user_ed25519.pub \
  --user existing-firewall-user \
  --principal existing-firewall-user
```

## Source References

- Netgate pfSense software and FreeBSD versions:
  https://docs.netgate.com/pfsense/en/latest/releases/versions.html
- OPNsense Community Edition release index:
  https://docs.opnsense.org/CE_releases.html
- OPNsense Business Edition release index:
  https://docs.opnsense.org/BE_releases.html
- OPNsense 24.1 release notes, FreeBSD 13.2:
  https://docs.opnsense.org/releases/CE_24.1.html
- OPNsense 24.7 release notes, FreeBSD 14.1:
  https://docs.opnsense.org/releases/CE_24.7.html
- OPNsense Business 24.4 release notes, based on Community 24.1.x:
  https://docs.opnsense.org/releases/BE_24.4.html
- OPNsense 25.1 release notes, FreeBSD 14.2:
  https://docs.opnsense.org/releases/CE_25.1.html
- OPNsense 25.7 release notes, FreeBSD 14.3:
  https://docs.opnsense.org/releases/CE_25.7.html
- OPNsense 26.1 release notes and 26.7 preparation notes:
  https://docs.opnsense.org/releases/CE_26.1.html
- VMActions public FreeBSD VM support matrix:
  https://github.com/vmactions/freebsd-vm
