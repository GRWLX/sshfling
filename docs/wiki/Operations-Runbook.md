# Operations Runbook

This runbook covers package release operations for SSHFling.

## Roles

| Role | Responsibility |
| --- | --- |
| Release operator | Runs package workflows, verifies outputs, records evidence, and coordinates rollback if needed. |
| Security reviewer | Confirms signing keys, repository trust, license constraints, and secret handling. |
| Platform owner | Confirms APT, RPM, macOS, Windows, and community package expectations for the release. |
| Support owner | Confirms install, uninstall, and troubleshooting docs are current. |

## Release-Day Procedure

1. Confirm the release commit is reviewed and ready.
2. Validate the version:

   ```bash
   bash packaging/resolve-version.sh 0.1.12
   ```

3. Run local tests:

   ```bash
   make test
   ```

4. Confirm release notes and docs match the implemented access contract:
   password access is the default, certificate access requires
   `--certificate`, `password prune` only removes expired tracked password
   grants, and package uninstall does not remove `/etc/sshfling` configuration
   or promise dependency-state rollback.
5. Confirm repository signing secrets are configured for production publishing.
6. Confirm GitHub Pages is configured for Actions.
   Optional manual `Release packages with public web` runs are dry-run
   verification unless `publish=true` is set; tag pushes publish after the
   package site is verified.
7. Run `Container image tests` manually with the release version, or confirm the
   same commit already passed the workflow.
8. Create and push the release tag:

   ```bash
   git tag -a v0.1.12 -m "SSHFling 0.1.12"
   git push origin v0.1.12
   ```

9. Watch the tag-triggered package workflows:

   - `Release packages without web`
   - `Release packages with public web`
   - `pages-build-deployment`

10. After Pages deploys, dispatch these workflows with version `0.1.12`:

   - `Package install tests`
   - `Cross OS validation`

11. Record the workflow URLs, tag, commit SHA, package-site URL, checksums URL,
   and signing key fingerprint in the release ticket.

## Post-Publish Smoke Checks

Check the public package site:

```bash
BASE_URL="https://grwlx.github.io/sshfling"
curl -fsSL "$BASE_URL/downloads/SHA256SUMS" -o /tmp/sshfling-SHA256SUMS
curl -fsSL "$BASE_URL/install.sh" -o /tmp/sshfling-install.sh
```

Run a convenience-wrapper smoke install on a disposable Debian or Ubuntu host:

```bash
BASE_URL="https://grwlx.github.io/sshfling"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL "$BASE_URL/install.sh" -o "$tmp/install.sh"
bash "$tmp/install.sh" apt
sshfling --version
```

Run a convenience-wrapper smoke install on a disposable RPM-family host:

```bash
BASE_URL="https://grwlx.github.io/sshfling"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL "$BASE_URL/install.sh" -o "$tmp/install.sh"
bash "$tmp/install.sh" dnf
sshfling --version
```

Use the workflow `Package install tests` and `Cross OS validation` results as
the official cross-platform evidence.

## Failure Handling

If `Release packages without web` fails:

- Do not publish the tag as complete.
- Fix the package build or tests on a new commit.
- Publish a new tag for the fixed version unless no external artifact has been
  consumed and your release policy allows replacing the tag.

If `Release packages with public web` fails before Pages deployment:

- Inspect the failed step.
- Fix package-site generation or missing artifacts.
- Rerun the workflow for the same version only when no package site was
  published from the failed run.

If `pages-build-deployment` fails:

- Confirm Pages is configured to deploy from Actions.
- Rerun the deployment after the configuration is fixed.
- Do not announce the release until the package site is reachable.

If `Package install tests` or `Cross OS validation` fails:

- Treat the release as not enterprise-ready.
- Identify whether the issue is package generation, package metadata,
  ecosystem-specific installation, or runtime behavior.
- Publish a fixed forward version after external consumption begins.

If the docs or release notes conflict with implemented access behavior:

- Treat the release as blocked for enterprise publication.
- Fix the docs before publishing when they misstate password default access,
  explicit certificate mode, prune cleanup limits, host uninstall flags, or
  package dependency-state limits.
- If a behavior change is intentional, record it as a breaking change and add a
  migration note before tagging.

## Rollback Guidance

Prefer fixed-forward releases for packages that may already be installed.
Package managers, caches, and community manifests make silent replacement of the
same version difficult to reason about.

Use same-version republishing only for package-site generation problems that are
caught before external consumption, and record the reason in the release ticket.

For Linux repository rollback:

- Publish a new corrected version.
- If the package site itself is broken, redeploy the last known-good package
  site artifact through the release process.
- Keep the repository signing key stable so existing clients can continue to
  verify metadata.

For endpoint rollback:

- Use the platform package manager to remove or downgrade according to your
  fleet policy.
- Package uninstall removes SSHFling package files and managed repository
  entries, but preserves host SSH configuration, password grant state, CA
  material, and `/etc/sshfling` policy/config files. Package-manager
  dependencies such as Python, OpenSSH, account-management tools, `procps`, and
  `util-linux` remain controlled by the host package manager and fleet policy.
- Run host cleanup only when you intend to remove SSHFling host configuration,
  CA material, policy files, or temporary password grant state.
- Follow the cleanup steps in the [README](../../README.md#uninstall-and-cleanup).

## Repository Signing Key Rotation

Rotate repository signing keys as a planned change:

1. Generate or approve the new key.
2. Update `SSHFLING_REPO_GPG_PRIVATE_KEY`.
3. Update `SSHFLING_REPO_GPG_FINGERPRINT` with the approved public fingerprint
   from the release/change record.
4. Set `SSHFLING_REPO_GPG_KEY_ID` when the imported keyring contains multiple
   keys.
5. Publish a package-site update.
6. Distribute the new public key to APT and RPM clients through configuration
   management.
7. Monitor install failures caused by stale trusted keys.

Key rotation changes client trust. Treat emergency rotation as an incident and
coordinate with fleet owners before removing the old key from managed hosts.

## Package-Site Incident Checklist

Use this checklist when installs fail from the public package site:

- Confirm `https://grwlx.github.io/sshfling/` is reachable.
- Confirm `downloads/SHA256SUMS` exists.
- Confirm `apt/Release`, `apt/Packages.gz`, and the expected `.deb` exist.
- Confirm `rpm/repodata/repomd.xml` and the expected `.rpm` exist.
- Confirm `sshfling-repo.gpg`, `sshfling-repo.asc`, `apt/InRelease`, and
  `rpm/repodata/repomd.xml.asc` exist when signed repositories are expected.
- Confirm the installer script references the expected package version.
- Compare failing host package-manager errors with the successful workflow logs.

## Operational Commands

List package version:

```bash
sshfling --version
```

Show effective policy:

```bash
sudo sshfling --json policy show
```

List active SSHFling sessions:

```bash
sudo sshfling --json list
```

Stop all active SSHFling sessions:

```bash
sudo sshfling shutdown
```

Prune expired temporary password grants:

```bash
sudo sshfling password prune
sudo sshfling password prune --all --delete-users
sudo sshfling password prune --username s234 --delete-users
```

Prune skips active grants. Use `--delete-users` only for expired Unix users
created by SSHFling; existing users explicitly allowed with
`--allow-existing-user` are locked and expired but are not deleted.
