# Firewall OS Version Index

This file records every pfSense and OPNsense version family found in the public
vendor documentation as of July 4, 2026, and maps each family to the closest
SSHFling public validation target.

The GitHub Actions matrix validates enterprise-safe x86_64 FreeBSD releases
currently listed by `vmactions/freebsd-vm`: 13.2, 13.3, 13.4, 13.5, 14.0,
14.1, 14.2, 14.3, 14.4, 15.0, and 15.1. FreeBSD 12.x firewall lines are
documented as historical mappings but are not active enterprise CI targets
because the remaining public package bootstrap path depends on an unsigned
OPNsense archive. Older FreeBSD 6.x through 11.x firewall lines are documented
but not tested because the public runner no longer boots those releases.
pfSense `16.0-CURRENT` lines are documented but not tested because there is no
public `16.0-CURRENT` runner in the VMActions matrix.

When the vendor documentation lists a future release without a public release
date, this index records `Vendor date not yet published` rather than a guessed
date.

## Public Runner Coverage

| FreeBSD runner | Firewall mapping | Validation claim |
| --- | --- | --- |
| 12.4 | pfSense Plus 21.x/22.x, pfSense CE 2.5.x/2.6.x, OPNsense HardenedBSD/FreeBSD 12.x-era releases | Historical mapping only; not active enterprise CI because the remaining public bootstrap archive is unsigned |
| 13.2 | OPNsense 22.x nearest, OPNsense 23.x, OPNsense 24.1, Business 23.10, Business 24.4 | Exact or nearest 13.x smoke |
| 13.3 | no direct firewall release mapping found | 13.x continuity smoke |
| 13.4 | no direct firewall release mapping found | 13.x continuity smoke |
| 13.5 | no direct firewall release mapping found | 13.x continuity smoke |
| 14.0 | pfSense Plus 23.x and pfSense CE 2.7.x | Major/minor `14.0-CURRENT` smoke |
| 14.1 | OPNsense 24.7 and Business 24.10 | Matching 14.1 smoke |
| 14.2 | OPNsense 25.1 and Business 25.4 | Matching 14.2 smoke |
| 14.3 | OPNsense 25.7, OPNsense 26.1, Business 25.10, Business 26.4 | Matching 14.3 smoke |
| 14.4 | no direct firewall release mapping found | 14.x continuity smoke |
| 15.0 | pfSense Plus 24.x/25.07.x and pfSense CE 2.8.x | Major/minor `15.0-CURRENT` smoke |
| 15.1 | OPNsense 26.7 preparation target | Tracking smoke |
| 16.0-CURRENT | pfSense Plus 25.11.x/26.x and planned pfSense CE 2.9.x | Public runner gap |

## pfSense Plus Versions

| Version | Released | FreeBSD base | SSHFling validation |
| --- | --- | --- | --- |
| 26.07 | Vendor date not yet published | `16.0-CURRENT@c215eef34550` | Public runner gap |
| 26.03.1 | 2026-05-27 | `16.0-CURRENT@c215eef34550` | Public runner gap |
| 26.03 | 2026-04-01 | `16.0-CURRENT@c215eef34550` | Public runner gap |
| 25.11.1 | 2026-01-26 | `16.0-CURRENT@44f3e9f7f6c9` | Public runner gap |
| 25.11 | 2025-12-11 | `16.0-CURRENT@44f3e9f7f6c9` | Public runner gap |
| 25.07.1 | 2025-08-18 | `15.0-CURRENT@bf06074106cf` | FreeBSD 15.0 VM, major/minor CURRENT coverage |
| 25.07 | 2025-08-04 | `15.0-CURRENT@bf06074106cf` | FreeBSD 15.0 VM, major/minor CURRENT coverage |
| 24.11 | 2024-11-25 | `15.0-CURRENT@f8a46de2dd48` | FreeBSD 15.0 VM, major/minor CURRENT coverage |
| 24.03 | 2024-04-23 | `15.0-CURRENT@a5a965d75934` | FreeBSD 15.0 VM, major/minor CURRENT coverage |
| 23.09.1 | 2023-12-07 | `14.0-CURRENT@0c783a37d5d5` | FreeBSD 14.0 VM, major/minor CURRENT coverage |
| 23.05.1 | 2023-06-29 | `14.0-CURRENT@0c59e0b4e581` | FreeBSD 14.0 VM, major/minor CURRENT coverage |
| 23.05 | 2023-05-22 | `14.0-CURRENT@0c59e0b4e581` | FreeBSD 14.0 VM, major/minor CURRENT coverage |
| 23.01 | 2023-02-15 | `14.0-CURRENT@aec9453fec7` | FreeBSD 14.0 VM, major/minor CURRENT coverage |
| 22.05.1 | 2022-12-06 | `12.3-STABLE@5f81a4619dcf` | FreeBSD 12.4 nearest 12.x smoke, not exact |
| 22.05 | 2022-06-26 | `12.3-STABLE@5f81a4619dcf` | FreeBSD 12.4 nearest 12.x smoke, not exact |
| 22.01 | 2022-02-14 | `12.3-STABLE@ef1e43df92c6` | FreeBSD 12.4 nearest 12.x smoke, not exact |
| 21.05.2 | 2021-10-26 | `12.2-STABLE@424f6363927` | FreeBSD 12.4 nearest 12.x smoke, not exact |
| 21.05.1 | 2021-08-05 | `12.2-STABLE@424f6363927` | FreeBSD 12.4 nearest 12.x smoke, not exact |
| 21.05 | 2021-06-02 | `12.2-STABLE@424f6363927` | FreeBSD 12.4 nearest 12.x smoke, not exact |
| 21.02.2 | 2021-04-13 | `12.2-STABLE@f4d0bc6aa6b` | FreeBSD 12.4 nearest 12.x smoke, not exact |
| 21.02-p1 | 2021-02-25 | `12.2-STABLE@f4d0bc6aa6b` | FreeBSD 12.4 nearest 12.x smoke, not exact |
| 21.02 | 2021-02-17 | `12.2-STABLE@f4d0bc6aa6b` | FreeBSD 12.4 nearest 12.x smoke, not exact |

## pfSense CE Versions

| Version | Released | FreeBSD base | SSHFling validation |
| --- | --- | --- | --- |
| 2.9.0 | Vendor date not yet published | `16.0-CURRENT@3f5f52216f7e` | Public runner gap |
| 2.8.1 | 2025-09-04 | `15.0-CURRENT@bf06074106cf` | FreeBSD 15.0 VM, major/minor CURRENT coverage |
| 2.8.0 | 2025-05-28 | `15.0-CURRENT@bf06074106cf` | FreeBSD 15.0 VM, major/minor CURRENT coverage |
| 2.7.2 | 2023-12-07 | `14.0-CURRENT@0c783a37d5d5` | FreeBSD 14.0 VM, major/minor CURRENT coverage |
| 2.7.1 | 2023-11-16 | `14.0-CURRENT@0c783a37d5d5` | FreeBSD 14.0 VM, major/minor CURRENT coverage |
| 2.7.0 | 2023-06-29 | `14.0-CURRENT@0c59e0b4e581` | FreeBSD 14.0 VM, major/minor CURRENT coverage |
| 2.6.0 | 2022-02-14 | `12.3-STABLE@ef1e43df92c6` | FreeBSD 12.4 nearest 12.x smoke, not exact |
| 2.5.2 | 2021-07-07 | `12.2-STABLE@f4d0bc6aa6b` | FreeBSD 12.4 nearest 12.x smoke, not exact |
| 2.5.1 | 2021-04-13 | `12.2-STABLE@f4d0bc6aa6b` | FreeBSD 12.4 nearest 12.x smoke, not exact |
| 2.5.0 | 2021-02-17 | `12.2-STABLE@f4d0bc6aa6b` | FreeBSD 12.4 nearest 12.x smoke, not exact |
| 2.4.5-p1 | 2020-06-09 | `11.3-STABLE@r357046` | Not in public CI |
| 2.4.5 | 2020-03-26 | `11.3-STABLE@r357046` | Not in public CI |
| 2.4.4-p3 | 2019-05-20 | `11.2-RELEASE-p10` | Not in public CI |
| 2.4.4-p2 | 2019-01-07 | `11.2-RELEASE-p4` | Not in public CI |
| 2.4.4-p1 | 2018-12-03 | `11.2-RELEASE-p4` | Not in public CI |
| 2.4.4 | 2018-09-24 | `11.2-RELEASE-p3` | Not in public CI |
| 2.4.3-p1 | 2018-05-14 | `11.1-RELEASE-p10` | Not in public CI |
| 2.4.3 | 2018-03-29 | `11.1-RELEASE-p7` | Not in public CI |
| 2.4.2-p1 | 2017-12-14 | `11.1-RELEASE-p6` | Not in public CI |
| 2.4.2 | 2017-11-20 | `11.1-RELEASE-p4` | Not in public CI |
| 2.4.1 | 2017-10-24 | `11.1-RELEASE-p2` | Not in public CI |
| 2.4 | 2017-10-12 | `11.1-RELEASE-p1` | Not in public CI |
| 2.3.5-p2 | 2018-05-14 | `10.3-RELEASE-p26` | Not in public CI |
| 2.3.5-p1 | 2017-12-14 | `10.3-RELEASE-p26` | Not in public CI |
| 2.3.5 | 2017-10-31 | `10.3-RELEASE-p20` | Not in public CI |
| 2.3.4-p1 | 2017-07-20 | `10.3-RELEASE-p19` | Not in public CI |
| 2.3.4 | 2017-05-04 | `10.3-RELEASE-p19` | Not in public CI |
| 2.3.3-p1 | 2017-03-09 | `10.3-RELEASE-p17` | Not in public CI |
| 2.3.3 | 2017-02-20 | `10.3-RELEASE-p16` | Not in public CI |
| 2.3.2 | 2016-07-19 | `10.3-RELEASE-p5` | Not in public CI |
| 2.3.1 | 2016-05-18 | `10.3-RELEASE-p3` | Not in public CI |
| 2.3 | 2016-04-12 | `10.3-RELEASE` | Not in public CI |
| 2.2.6 | 2015-12-21 | `10.1-RELEASE-p25` | Not in public CI |
| 2.2.5 | 2015-11-05 | `10.1-RELEASE-p24` | Not in public CI |
| 2.2.4 | 2015-07-26 | `10.1-RELEASE-p15` | Not in public CI |
| 2.2.3 | 2015-06-24 | `10.1-RELEASE-p13` | Not in public CI |
| 2.2.2 | 2015-04-15 | `10.1-RELEASE-p9` | Not in public CI |
| 2.2.1 | 2015-03-17 | `10.1-RELEASE-p6` | Not in public CI |
| 2.2 | 2015-01-23 | `10.1-RELEASE-p4` | Not in public CI |
| 2.1.5 | 2014-08-27 | `8.3-RELEASE-p16` | Not in public CI |
| 2.1.4 | 2014-06-25 | `8.3-RELEASE-p16` | Not in public CI |
| 2.1.3 | 2014-05-02 | `8.3-RELEASE-p16` | Not in public CI |
| 2.1.2 | 2014-04-10 | `8.3-RELEASE-p14` | Not in public CI |
| 2.1.1 | 2014-04-04 | `8.3-RELEASE-p14` | Not in public CI |
| 2.1 | 2013-09-15 | `8.3-RELEASE-p11` | Not in public CI |
| 2.0.3 | 2013-04-15 | `8.1-RELEASE-p13` | Not in public CI |
| 2.0.2 | 2012-12-21 | `8.1-RELEASE-p13` | Not in public CI |
| 2.0.1 | 2011-12-20 | `8.1-RELEASE-p6` | Not in public CI |
| 2.0 | 2011-09-17 | `8.1-RELEASE-p4` | Not in public CI |
| 1.2.3 | 2009-12-10 | `7.2-RELEASE-p5` | Not in public CI |
| 1.2.2 | 2009-01-09 | `7.0-RELEASE-p8` | Not in public CI |
| 1.2.1 | 2008-12-26 | `7.0-RELEASE-p7` | Not in public CI |
| 1.2 | 2008-02-25 | `6.2-RELEASE-p11` | Not in public CI |

## OPNsense Community Edition Series

OPNsense publishes the public CE release index by series. The rows below cover
every CE series linked from that index.

| Series | Base found in release notes | SSHFling validation |
| --- | --- | --- |
| 26.1 | 14.3 line, with FreeBSD 15.1 support work noted | FreeBSD 14.3 VM plus FreeBSD 15.1 tracking VM |
| 25.7 | FreeBSD 14.3 | FreeBSD 14.3 VM |
| 25.1 | FreeBSD 14.2 | FreeBSD 14.2 VM |
| 24.7 | FreeBSD 14.1 | FreeBSD 14.1 VM |
| 24.1 | FreeBSD 13.2 | FreeBSD 13.2 VM |
| 23.7 | FreeBSD 13.2 | FreeBSD 13.2 VM |
| 23.1 | FreeBSD 13.1, with 13.2 preparation notes | FreeBSD 13.2 nearest 13.x smoke |
| 22.7 | FreeBSD 13.1 | FreeBSD 13.2 nearest 13.x smoke |
| 22.1 | FreeBSD 13.0 / 13.1-era notes | FreeBSD 13.2 nearest 13.x smoke |
| 21.7 | HardenedBSD 12.1, with FreeBSD 13 planning notes | FreeBSD 12.4 nearest 12.x smoke |
| 21.1 | older 12.x-era base; page references FreeBSD 13 tooling notes only | FreeBSD 12.4 nearest 12.x smoke |
| 20.7 | HardenedBSD 12.1 | FreeBSD 12.4 nearest 12.x smoke |
| 20.1 | HardenedBSD 12.1 | FreeBSD 12.4 nearest 12.x smoke |
| 19.7 | HardenedBSD-era base; no exact base extracted from release page | Not in public CI |
| 19.1 | HardenedBSD 11.2 / FreeBSD 11.1-era notes | Not in public CI |
| 18.7 | HardenedBSD 11.2 / FreeBSD 11.2-era notes | Not in public CI |
| 18.1 | FreeBSD 11.1 | Not in public CI |
| 17.7 | FreeBSD 11.0 to 11.1 transition notes | Not in public CI |
| 17.1 | FreeBSD 11.0 | Not in public CI |
| 16.7 | FreeBSD 10.3, with FreeBSD 11.0 preparation notes | Not in public CI |
| 16.1 | FreeBSD 10.2-era notes | Not in public CI |
| 15.7 | FreeBSD 10.1 / 10.2-era notes | Not in public CI |
| 15.1 | FreeBSD 10.0 / 10.1-era notes | Not in public CI |

## OPNsense Business Edition Series

OPNsense publishes the public BE release index by series. The rows below cover
every BE series linked from that index.

| Series | Base found in release notes | SSHFling validation |
| --- | --- | --- |
| 26.4 | based on OPNsense 26.1.x community releases | FreeBSD 14.3 VM plus FreeBSD 15.1 tracking VM |
| 25.10 | FreeBSD 14.3 | FreeBSD 14.3 VM |
| 25.4 | FreeBSD 14.2 | FreeBSD 14.2 VM |
| 24.10 | FreeBSD 14.1 | FreeBSD 14.1 VM |
| 24.4 | based on OPNsense 24.1.x / FreeBSD 13.2 | FreeBSD 13.2 VM |
| 23.10 | FreeBSD 13.2 | FreeBSD 13.2 VM |
| 23.4 | FreeBSD 13 stable | FreeBSD 13.2 nearest 13.x smoke |
| 22.10 | FreeBSD 13.1 | FreeBSD 13.2 nearest 13.x smoke |
| 22.4 | FreeBSD 13.0 / 13-STABLE | FreeBSD 13.2 nearest 13.x smoke |
| 21.10 | based on OPNsense 21.7.x community releases | FreeBSD 12.4 nearest 12.x smoke |
| 21.4 | OPNsense 21.x / FreeBSD 12.x-era release | FreeBSD 12.4 nearest 12.x smoke |
| 20.7 | HardenedBSD 12.1 | FreeBSD 12.4 nearest 12.x smoke |
| 20.1 | HardenedBSD 12.1 | FreeBSD 12.4 nearest 12.x smoke |
| 19.7 | HardenedBSD-era base; no exact base extracted from release page | Not in public CI |
| 19.1 | HardenedBSD 11.2 / FreeBSD 11.1-era notes | Not in public CI |

## Sources

- Netgate pfSense software and FreeBSD versions:
  https://docs.netgate.com/pfsense/en/latest/releases/versions.html
- OPNsense Community Edition release index:
  https://docs.opnsense.org/CE_releases.html
- OPNsense Business Edition release index:
  https://docs.opnsense.org/BE_releases.html
- OPNsense FreeBSD:12 package snapshot previously used for historical 12.4
  experiments; not used by enterprise CI because it is unsigned:
  https://pkg.opnsense.org/FreeBSD:12:amd64/snapshots/latest/
- VMActions public FreeBSD VM support matrix:
  https://github.com/vmactions/freebsd-vm
