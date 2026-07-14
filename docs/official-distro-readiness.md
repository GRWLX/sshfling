# Official Distro Repository Readiness

This evidence is for publication through official Debian, Ubuntu, Fedora, and EPEL repositories. It is separate from the upstream signed APT/DNF repository.

Current candidate: `v0.1.24`.

Current public release packet:
`https://github.com/GRWLX/sshfling/releases/tag/v0.1.24`

Status meanings:

- `PASS`: sufficient evidence exists for this readiness item.
- `WARN`: usable for upstream packaging, but not enough for official archive submission.
- `BLOCKED`: do not submit to the official archive until resolved.

| Area | Status | Evidence | Required next action |
| --- | --- | --- | --- |
| License | PASS | LICENSE declares Apache License, Version 2.0. | Confirm package metadata preserves Apache-2.0 license files and required notices. |
| Debian/Ubuntu source packaging | WARN | `v0.1.24` source package assets, lintian log, ITP draft, RFS draft, dput example, and upload commands are in the official distro submission packet. | File WNPP/ITP, sign/upload to mentors from a maintainer machine, file RFS, and respond to sponsor review. |
| Debian/Ubuntu maintainer metadata | PASS | debian/control does not use the known placeholder maintainer. | Confirm the maintainer identity matches the sponsor or uploader process. |
| Generated DEB metadata | PASS | Generated DEB metadata does not use the known placeholder maintainer. | Keep generated upstream repository packages aligned with official Debian metadata where practical. |
| Fedora/EPEL source packaging | WARN | `v0.1.24` spec, SRPM, source tarball, rpmlint log, mock command, fedora-review command, and package-review draft are in the official distro submission packet. | Run mock and fedora-review on a Fedora packaging host, then submit Fedora package review before EPEL branches. |
| Fedora/EPEL spec license metadata | PASS | packaging/fedora/sshfling.spec records Apache-2.0. | Confirm the spec License field remains a Fedora-accepted license expression during package review. |
| Generated RPM license metadata | PASS | packaging/build-rpm.sh emits Apache-2.0. | Keep generated upstream RPM metadata aligned with the Fedora review spec where practical. |
| Package build/test coverage | PASS | Generated DEB/RPM builders, local install validation, and package-install workflow are present. | Keep these as upstream smoke tests while adding distro-native source package tests. |
| Official distro draft validation | PASS | Repeatable local and CI validation exists for Debian and Fedora packaging drafts, including lintian and rpmlint logs plus a validated submission packet builder for source artifacts and review request drafts. | Run mock and fedora-review before formal Fedora package review, then submit the prepared packet through maintainer accounts. |

## Submission Path

1. Keep Apache-2.0 metadata consistent across source, generated packages, and distro drafts.
2. Run `make official-distro-submission-prepare` to build Debian source artifacts, Fedora SRPM/spec artifacts, lint logs, hashes, and request drafts.
3. File a Debian WNPP/ITP bug, sign and upload the source package to mentors.debian.net, then file an RFS bug and find a Debian sponsor.
4. Let Ubuntu sync from Debian when possible; otherwise request Ubuntu sponsorship for a source package.
5. Validate the Fedora SRPM/spec with `mock` and `fedora-review`, then file Fedora package review.
6. Request EPEL branches only after Fedora package acceptance.

## Current Decision Gate

No `BLOCKED` rows remain. Rows with `WARN` still need maintainer or sponsor review before upload.
