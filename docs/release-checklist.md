# SSHFling Release Checklist

Use this checklist before publishing enterprise package artifacts.

## Branch and Tag Assumptions

- Release from `main` after it is up to date with `origin/main` and required CI is green.
- Use a short-lived `release/vX.Y.Z` branch only when final stabilization needs more than one commit.
- Tags are named `vX.Y.Z`; package workflow inputs use `X.Y.Z`.
- Package versions currently require exactly three numeric components, enforced by `packaging/version.sh`.
- Do not move or replace a published release tag. Publish a new patch version instead.

## Working Tree Hygiene

- `git status --short --branch` is clean before tagging, apart from intentional release-note edits.
- Generated package outputs stay out of source commits: `build/`, `dist/`, `public/`, `package-dist/`, and `release-dist/`.
- Remove interpreter caches and local byproducts such as `__pycache__/`, `.pytest_cache/`, and local logs.
- Check that no local secrets or package credentials are staged: `.env`, `.env.*`, private keys, package-manager credentials, and non-placeholder `secrets/` files.
- Run `make clean` before rebuilding local package artifacts from the exact candidate commit.

## Release Notes

- Use GitHub generated release notes as a starting point, then add a short enterprise-facing summary.
- Call out security-relevant behavior changes, install or uninstall changes, upgrade impact, policy defaults, and compatibility notes.
- Confirm access behavior is described accurately: password access is the default, certificate access requires `--certificate`, and certificate-specific setup options are not implicit.
- Confirm cleanup behavior is described accurately: `password prune` removes expired tracked grants only, `--all` does not remove active grants, `--delete-users` only deletes expired SSHFling-created users, break-glass existing-user grants are locked/expired but not deleted, and package uninstall preserves `/etc/sshfling` configuration without restoring dependency state.
- List supported package artifacts and target ecosystems for the release.
- Include checksum location and the signing-key fingerprint used for APT/RPM metadata, or explicitly state when a generated test key was used.
- Record validation workflow links for `Container image tests`, `Release packages without web`, `Release packages with public web`, `Package install tests`, and `Cross OS validation`.

## Build and Validation

- Run local validation:

```bash
make test
make test-containers
```

- Run release workflows with the same `X.Y.Z` version input:

1. `Container image tests`
2. `Release packages without web`
3. `Release packages with public web`, using tag publishing or `publish=true`
   only when the production signing key is configured
4. `pages-build-deployment`
5. `Package install tests`
6. `Cross OS validation`

- Confirm release assets include the expected `.deb`, `.rpm`, `.pkg`, `.msi`, Windows zip, source tarball, and `SHA256SUMS`.
- Confirm the public package site has APT/RPM metadata, repository signing files when production signing is enabled, Homebrew and macOS installer scripts, Windows installer scripts, and generated community manifests.

## Publish Gate

- Confirm version references agree across `bin/sshfling`, `Makefile`, package metadata, release workflow input, tag name, and release notes.
- Confirm `LICENSE` and commercial distribution language are included in package templates and public package pages.
- Tag only after the release commit is merged and validation inputs are final.
- After publishing, verify the GitHub release, GitHub Pages package site, direct download URLs, checksums, and at least one clean install path from a fresh host or container.

## Release Blockers

Do not publish an enterprise release until these are fixed or formally excepted:

- Docs or release notes describe certificate access as the default.
- Docs or release notes omit that certificate setup requires `--certificate`.
- Docs or release notes overstate `password prune` cleanup by implying active grants or unmanaged records are removed, or by implying existing users are deleted instead of locked/expired.
- Docs or release notes imply package uninstall removes `/etc/sshfling` configuration or restores package-manager dependencies such as Python, OpenSSH, account-management tools, `procps`, or `util-linux`.
- Production APT/RPM repository publication uses an ephemeral signing key, lacks an approved repository signing fingerprint, or requires weak trust settings such as `trusted=yes`, `gpgcheck=0`, or `repo_gpgcheck=0`.
- Required macOS notarization, Windows Authenticode signing, release approval, validation evidence, rollback owner, or exception records are missing.
- The release claims SOC 2, ISO 27001, NIST, FedRAMP, or similar compliance certification without an approved external attestation or certification record.
