# Release Signing and Official Distro Handoff

This handoff covers the external credentials and account actions required after
the source, package drafts, and official-distro submission packet are ready.

## Current Candidate

- Release tag: `v0.1.23`
- Source commit: `d4d16d80b484f7f4fb7eb2c698887288a1918e32`
- GitHub prerelease: `https://github.com/GRWLX/sshfling/releases/tag/v0.1.23`
- Official distro packet asset: `sshfling-0.1.23-official-distro-submission.tar.gz`

The tag has passing Java package, GHCR image, official distro draft, language
runtime, and container validation evidence. The full Windows/macOS release
package workflows remain blocked until signing credentials are configured.

## GitHub Signing Configuration

Keep release-tag Windows and macOS jobs fail-closed. Do not disable the signing
gates for a public release that advertises `.msi` or `.pkg` installers.

Configure these in the repository or protected `release-signing` environment.

Windows Authenticode:

- Variable: `SSHFLING_WINDOWS_REQUIRE_AUTHENTICODE=true`
- Secret: `SSHFLING_WINDOWS_SIGN_CERT_SHA1`
- Secret: `SSHFLING_WINDOWS_SIGN_CERT_PFX_BASE64`
- Secret: `SSHFLING_WINDOWS_SIGN_CERT_PASSWORD`
- Variable: `SSHFLING_WINDOWS_SIGN_TIMESTAMP_URL`

macOS package signing:

- Variable: `SSHFLING_PKG_REQUIRE_SIGNING=true`
- Secret: `SSHFLING_PKG_SIGN_IDENTITY`
- Secret: `SSHFLING_PKG_SIGN_CERT_P12_BASE64`
- Secret: `SSHFLING_PKG_SIGN_CERT_PASSWORD`
- Variable: `SSHFLING_PKG_SIGN_TIMESTAMP`

macOS notarization:

- Variable: `SSHFLING_PKG_REQUIRE_NOTARIZATION=true`
- Secret: `SSHFLING_PKG_NOTARY_PROFILE`
- Secret: `SSHFLING_PKG_NOTARY_APPLE_ID`
- Secret: `SSHFLING_PKG_NOTARY_TEAM_ID`
- Secret: `SSHFLING_PKG_NOTARY_PASSWORD`

After configuration, rerun the release package workflows from a new patch tag.
Do not move an already-pushed tag.

## Debian and Ubuntu

Use the `v0.1.23` release assets as the current submission packet.

1. Download and review `sshfling-0.1.23-official-distro-submission.tar.gz`.
2. File the Debian WNPP/ITP bug using `debian/ITP.txt`.
3. Replace `#ITP_BUG_NUMBER` in `debian/RFS.txt` and the package changelog if a
   sponsor asks for the exact bug closure before upload.
4. Rebuild from a new patch commit if the ITP bug number is committed into
   packaging.
5. Sign `debian/sshfling_0.1.23-1_source.changes` on the maintainer machine.
6. Upload to mentors with the generated `debian/dput.cf.example` and
   `debian/upload-commands.txt`.
7. File the RFS bug using `debian/RFS.txt` after the mentors package page is
   available.
8. Address sponsor review comments with new commits and new patch tags.

Prefer Debian-first for Ubuntu. Request Ubuntu sync after Debian acceptance
unless Ubuntu-specific packaging is required.

## Fedora and EPEL

Use these `v0.1.23` release assets for Fedora package review:

- `sshfling.spec`
- `sshfling-0.1.23-1.src.rpm`
- `fedora-package-review-v0.1.23.md`

Expected account and review flow:

1. Confirm Fedora Account System and Bugzilla access.
2. Run `mock -r fedora-rawhide-x86_64 --rebuild sshfling-0.1.23-1.src.rpm` on a
   Fedora packaging host.
3. Run `fedora-review -n sshfling --rpm-spec sshfling.spec --srpm sshfling-0.1.23-1.src.rpm`
   if `fedora-review` is available.
4. File the Fedora package review with the generated draft.
5. Respond to reviewer comments with new commits and new patch tags.
6. Import to Fedora dist-git only after approval.
7. Request EPEL branches after Fedora acceptance unless a sponsor explicitly
   asks for an EPEL-only path.

## Evidence to Keep

- GitHub release URL and asset list.
- `SHA256SUMS` from the official distro packet.
- Debian `lintian-source.log`.
- Fedora `rpmlint-source.log`, plus local `mock` and `fedora-review` logs.
- GitHub Actions run URLs for Java package, GitHub Packages, official distro
  drafts, language runtime validation, and container image tests.
- Signing/notarization evidence once Windows and macOS signing credentials are
  configured.
