# Official Distro Submission Runbook

This runbook prepares the artifacts needed for official Debian, Ubuntu,
Fedora, and EPEL submission. It does not replace maintainer accounts, GPG keys,
Bugzilla/Fedora accounts, Debian sponsor review, Fedora package review, or
archive maintainers.

## Build the Packet

From a clean committed tree:

```bash
make official-distro-submission-prepare
make official-distro-submission-validate
```

The command writes `build/official-distro-submission/` with:

- Debian source package artifacts: `.dsc`, `.orig.tar.gz`, `.debian.tar.*`,
  source `.changes`, source `.buildinfo`, and `lintian-source.log`.
- Debian request drafts: `ITP.txt`, `RFS.txt`, `dput.cf.example`, and
  `upload-commands.txt`.
- Fedora review artifacts: `sshfling.spec`, expanded spec, source tarball,
  SRPM, `rpmlint-source.log`, `package-review.md`, `mock-command.txt`, and
  `fedora-review-command.txt`.
- `SHA256SUMS` for the packet.

The validate target checks packet hashes, required Debian and Fedora files,
lint logs, request drafts, and source tarball exclusions.

For the final maintainer handoff after creating and pushing the matching
version tag, run the strict tag gate:

```bash
SSHFLING_REQUIRE_RELEASE_TAG=1 make official-distro-submission-validate
```

Strict mode requires the packet README to show that `vVERSION` points at the
same source commit as the generated Debian and Fedora artifacts.

Use `SSHFLING_OFFICIAL_SUBMISSION_DIR=/path/to/output` to choose a different
output directory. Use `SSHFLING_ALLOW_DIRTY=1` only for a local rehearsal, not
for an actual submission packet.

## Debian

1. Review `build/official-distro-submission/debian/ITP.txt`.
2. File the WNPP/ITP bug with Debian BTS.
3. Replace `#ITP_BUG_NUMBER` in `RFS.txt` and `debian/changelog`.
4. Rebuild the packet from the updated commit.
5. Sign the source `.changes` file on the maintainer machine:

```bash
debsign build/official-distro-submission/debian/sshfling_VERSION-1_source.changes
```

6. Configure `dput` from `dput.cf.example`.
7. Upload to mentors:

```bash
dput mentors build/official-distro-submission/debian/sshfling_VERSION-1_source.changes
```

8. File the RFS bug against `sponsorship-requests` using `RFS.txt`.
9. Respond to sponsor review, update packaging, and rebuild the packet until
   the sponsor is ready to upload.

## Ubuntu

Prefer Debian-first packaging. After Debian acceptance, request Ubuntu sync
where practical. Use Ubuntu sponsorship only when an Ubuntu-specific source
package is required.

## Fedora

1. Upload or attach the files in `build/official-distro-submission/fedora/`:
   `sshfling.spec`, `sshfling-*.src.rpm`, and supporting logs.
2. Run the generated mock command on a Fedora packaging host and keep the log:

```bash
cd build/official-distro-submission/fedora
mock -r fedora-rawhide-x86_64 --rebuild sshfling-VERSION-1.src.rpm
```

3. Run the generated Fedora review command if `fedora-review` is available:

```bash
cd build/official-distro-submission/fedora
fedora-review -n sshfling --rpm-spec sshfling.spec --srpm sshfling-VERSION-1.src.rpm
```

4. File the Fedora package review using `package-review.md` as the draft.
5. After review acceptance, import into Fedora dist-git through the normal
   Fedora package maintainer flow.

## EPEL

Request EPEL branches after Fedora acceptance. Use an EPEL-only path only if a
Fedora/EPEL sponsor explicitly asks for it.

## Evidence

Keep these with the review tickets:

- `docs/official-distro-readiness.md`
- `build/official-distro-submission/SHA256SUMS`
- Debian `lintian-source.log`
- Fedora `rpmlint-source.log`
- mock and `fedora-review` logs, when run
- Links to Debian ITP/RFS and Fedora package review tickets
