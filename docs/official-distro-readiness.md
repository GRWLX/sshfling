# Official Distro Repository Readiness

This evidence is for publication through official Debian, Ubuntu, Fedora, and EPEL repositories. It is separate from the upstream signed APT/DNF repository.

Status meanings:

- `PASS`: sufficient evidence exists for this readiness item.
- `WARN`: usable for upstream packaging, but not enough for official archive submission.
- `BLOCKED`: do not submit to the official archive until resolved.

| Area | Status | Evidence | Required next action |
| --- | --- | --- | --- |
| License | BLOCKED | LICENSE declares SSHFling proprietary, not open source, paid-use, and redistribution-restricted. | Choose an OSI/DFSG/Fedora-acceptable open-source license or obtain a distro-specific redistribution grant before official archive submission. |
| Debian/Ubuntu source packaging | WARN | Required debian/ source package files are present as a draft. | Build and lint the source package, then prepare WNPP/ITP and sponsorship materials. |
| Debian/Ubuntu maintainer metadata | WARN | debian/control still uses placeholder Maintainer metadata. | Replace placeholder maintainer metadata with the accountable Debian/Ubuntu maintainer or team before upload. |
| Generated DEB metadata | WARN | packaging/build-deb.sh still emits placeholder Maintainer metadata. | Replace placeholder maintainer metadata in generated packages and keep generated DEBs separate from official Debian source packaging. |
| Fedora/EPEL source packaging | WARN | A checked-in RPM spec path exists as a draft. | Validate the spec with rpmlint/mock/fedora-review and submit a Fedora package review before EPEL branches. |
| Fedora/EPEL spec license metadata | BLOCKED | packaging/fedora/sshfling.spec records LicenseRef-SSHFling-Commercial. | Change the Fedora spec License field only after the project license is changed or a Fedora-acceptable redistribution grant is approved. |
| Generated RPM license metadata | BLOCKED | packaging/build-rpm.sh emits LicenseRef-SSHFling-Commercial. | Change RPM license metadata only after the project license is changed or an explicit redistribution grant is approved. |
| Package build/test coverage | PASS | Generated DEB/RPM builders, local install validation, and package-install workflow are present. | Keep these as upstream smoke tests while adding distro-native source package tests. |
| Official distro draft validation | PASS | Repeatable local and CI validation exists for Debian and Fedora packaging drafts. | Run lintian, autopkgtest, rpmlint, mock, and fedora-review after the license and maintainer gates are resolved. |

## Submission Path

1. Resolve the license gate before asking distro maintainers to review the package.
2. Add Debian source packaging and validate it with `dpkg-buildpackage`, `lintian`, and `autopkgtest`.
3. File a Debian WNPP/ITP bug, upload to mentors.debian.net, and find a Debian sponsor.
4. Let Ubuntu sync from Debian when possible; otherwise request Ubuntu sponsorship for a source package.
5. Add a Fedora-compliant spec and SRPM, validate with `rpmlint`, `mock`, and `fedora-review`, then file Fedora package review.
6. Request EPEL branches only after Fedora package acceptance.

## Current Decision Gate

The repository is not ready for official Debian/Ubuntu/Fedora/EPEL submission while any `BLOCKED` row remains.
