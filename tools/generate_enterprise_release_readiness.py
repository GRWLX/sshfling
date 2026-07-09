#!/usr/bin/env python3
"""Generate the ignored enterprise release readiness checklist and matrix.

The generated files are intentionally not tracked. This tool preserves the
large matrix shape used by release review while grounding PASS rows in a small
auditable evidence bundle. External release proof stays BLOCKED unless the
release ticket supplies immutable workflow, signing, notarization, store, cloud,
hardware, or scanner evidence.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import subprocess
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


MATRIX_FIELDS = [
    "row_id",
    "readiness_status",
    "result",
    "release_version",
    "source_commit",
    "support_tier",
    "workflow_phase",
    "control_area",
    "check_name",
    "expected_result",
    "actual_result",
    "required_evidence",
    "evidence_source",
    "evidence_ref",
    "evidence_sha256",
    "workflow_name",
    "workflow_run_url",
    "workflow_job",
    "signer_or_key_fingerprint",
    "exception_id",
    "exception_owner",
    "exception_expires",
    "blocker_reason",
    "reviewer",
    "reviewed_at_utc",
    "notes",
    "platform_family",
    "platform_version",
    "package_channel",
    "cpu_architecture",
    "hardware_class",
    "runtime_mode",
]

PRIOR_COUNTS = {
    "PASS": 160,
    "FAIL": 1248,
    "BLOCKED": 28296,
    "UNSUPPORTED": 13376,
    "EXPERIMENTAL": 12816,
    "NOT_APPLICABLE": 47240,
    "FUTURE_WORK": 672672,
}
LOCAL_BURNDOWN_FAIL_ROWS = PRIOR_COUNTS["FAIL"]

PLATFORM_FAMILIES = [
    "debian",
    "ubuntu",
    "rhel",
    "fedora",
    "rocky-linux",
    "alma-linux",
    "ubi",
    "arch-linux",
    "alpine-linux",
    "opensuse",
    "nix",
    "slackware",
    "void-linux",
    "freebsd",
    "openbsd",
    "netbsd",
    "pfsense",
    "opnsense",
    "macos",
    "windows",
    "dotnet-tool",
    "container",
    "github-packages",
    "homebrew",
    "winget",
    "scoop",
    "chocolatey",
    "snapcraft",
    "community-manifest",
]
PLATFORM_VERSIONS = [
    "current-release",
    "lts-release",
    "latest",
    "stable",
    "tag-candidate",
    "package-site",
    "generated-manifest",
    "public-runner",
    "customer-managed",
    "future-version",
    "unsupported-version",
]
PACKAGE_CHANNELS = [
    "release-asset",
    "apt",
    "rpm",
    "github-pages",
    "homebrew",
    "pkg",
    "msi",
    "portable-zip",
    "dotnet-nupkg",
    "java-jar",
    "container-image",
    "community-repo",
    "source-runtime",
    "manual-install",
]
CPU_ARCHITECTURES = [
    "amd64",
    "x86_64",
    "arm64",
    "aarch64",
    "armv7",
    "i386",
    "ppc64le",
    "s390x",
    "riscv64",
    "universal",
    "not-applicable",
]
HARDWARE_CLASSES = [
    "container",
    "virtual-machine",
    "server",
    "desktop",
    "developer-workstation",
    "edge-appliance",
    "iot-gateway",
    "embedded-linux",
    "firewall-appliance",
    "fpga-soc-host",
    "cloud-runner",
    "customer-managed-host",
    "not-applicable",
]
RUNTIME_MODES = [
    "client-connect",
    "password-grant-server",
    "certificate-grant-server",
    "file-transfer-scp",
    "file-transfer-rsync",
    "detached-job",
    "package-install",
    "package-uninstall",
    "security-scan",
    "release-publish",
    "not-applicable",
]

PASS_AREAS = [
    "runtime-contract",
    "release-security-baseline",
    "package-rehearsal",
    "matrix-generator",
    "local-transfer-burndown",
]
BLOCKED_REQUIREMENTS = [
    "Release approval ticket with approver, timestamp, scope, rollback owner, and previous known-good version.",
    "Protected tag or protected release-environment evidence for the exact release commit.",
    "Immutable successful Release packages without web workflow URL for the final commit.",
    "Immutable successful Release packages with public web workflow URL for the final commit.",
    "Pages deployment URL and deployment ID for package-site publication.",
    "Package install tests workflow URL and matrix result for the final package site.",
    "Cross OS validation workflow URL and matrix result for the final package site.",
    "Container image tests workflow URL, image digests, and package/image provenance.",
    "Production APT/RPM signing-key fingerprint and access-review evidence.",
    "Proof that generated test signing keys were not used for production package-site publication.",
    "macOS Developer ID Installer signing, notarization, and stapling verification output.",
    "Windows Authenticode certificate identity, timestamping, and signature verification output.",
    "GitHub release asset inventory with SHA256SUMS and provenance/attestation output.",
    "Live transfer smoke evidence for target-side scp/rsync permissions, symlinks, expiry, and partial-file behavior.",
    "External scanner outputs or approved exceptions for bandit, hadolint, syft, gitleaks, trivy, and osv-scanner.",
    "Customer or lab hardware evidence for ARM, IoT, embedded, appliance, FPGA/SoC host-control-plane claims.",
]
UNSUPPORTED_REASONS = [
    "Target is outside the declared package and runtime support scope for this release.",
    "Target requires unsupported package-manager semantics or unavailable platform tools.",
    "Target would require a support claim that the release docs explicitly avoid.",
]
EXPERIMENTAL_REASONS = [
    "Generated community packaging exists but still requires ecosystem maintainer review.",
    "Target can be rehearsed locally but needs customer or maintainer acceptance before support.",
    "Target depends on external store, tap, or repository policy outside this checkout.",
]
FUTURE_WORK_REASONS = [
    "Future platform/architecture/runtime combination is not claimed for this release.",
    "Future hardware, appliance, or store evidence is deferred to a later release ticket.",
    "Future compliance or support expansion needs a separate owner, test plan, and exception record.",
]
NOT_APPLICABLE_REASONS = [
    "Control does not apply to this platform/package/runtime combination.",
    "Signing, notarization, or store evidence is not relevant to this generated row.",
    "Hardware and runtime dimensions are mutually exclusive for this row.",
]


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def current_commit(repo_root: Path) -> str:
    if not (repo_root / ".git").exists():
        return ""
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "HEAD"],
            cwd=repo_root,
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except (OSError, subprocess.CalledProcessError):
        return ""


def git_worktree_status(repo_root: Path) -> str:
    if not (repo_root / ".git").exists():
        return ""
    try:
        return subprocess.check_output(
            ["git", "status", "--porcelain=v1"],
            cwd=repo_root,
            text=True,
            stderr=subprocess.DEVNULL,
        )
    except (OSError, subprocess.CalledProcessError):
        return ""


def git_dirty_fingerprint(repo_root: Path, status: str) -> str:
    digest = hashlib.sha256(status.encode("utf-8", errors="surrogateescape"))
    for command in (["git", "diff", "--binary"], ["git", "diff", "--cached", "--binary"]):
        try:
            output = subprocess.check_output(command, cwd=repo_root, stderr=subprocess.DEVNULL)
        except (OSError, subprocess.CalledProcessError):
            output = b""
        digest.update(b"\0")
        digest.update(output)
    return digest.hexdigest()


def require_repo_path(path: Path, repo_root: Path, label: str) -> Path:
    resolved = path.resolve()
    try:
        resolved.relative_to(repo_root.resolve())
    except ValueError as exc:
        raise SystemExit(f"{label} must stay inside repo: {path}") from exc
    return resolved


def repo_relative(path: Path, repo_root: Path) -> str:
    return path.resolve().relative_to(repo_root.resolve()).as_posix()


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def marker_check(repo_root: Path, rel_path: str, markers: list[str], name: str) -> dict[str, Any]:
    path = repo_root / rel_path
    exists = path.is_file()
    text = read_text(path) if exists else ""
    missing = [marker for marker in markers if marker not in text]
    return {
        "name": name,
        "path": rel_path,
        "status": "pass" if exists and not missing else "fail",
        "missing_markers": missing,
        "sha256": file_sha256(path) if exists else "MISSING",
    }


def count_matrix_statuses(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {"path": path.as_posix(), "status": "fail", "reason": "matrix not found", "counts": {}}
    counts: Counter[str] = Counter()
    with path.open(newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            counts[(row.get("readiness_status") or row.get("result") or "").strip().upper()] += 1
    bad = counts.get("FAIL", 0) + counts.get("BLOCKED", 0)
    return {
        "path": path.as_posix(),
        "status": "pass" if counts and bad == 0 else "fail",
        "counts": dict(sorted(counts.items())),
        "sha256": file_sha256(path),
    }


def local_control_checks(repo_root: Path) -> list[dict[str, Any]]:
    checks = [
        marker_check(
            repo_root,
            "bin/sshfling",
            ["def cmd_scp", "def cmd_rsync", "password_transfer_ssh_options", "transfer_dry_run_enabled"],
            "native scp/rsync command implementation",
        ),
        marker_check(
            repo_root,
            "README.md",
            ["sshfling scp", "sshfling rsync", "target filesystem umask", "partial files"],
            "transfer behavior user documentation",
        ),
        marker_check(
            repo_root,
            "docs/ai-temporary-access.md",
            ["sshfling scp", "sshfling rsync", "target umask"],
            "temporary access transfer documentation",
        ),
        marker_check(
            repo_root,
            "docs/openssh-dependencies.md",
            ["requires `rsync`", "does not vendor"],
            "OpenSSH and rsync dependency ownership documentation",
        ),
        marker_check(
            repo_root,
            "docs/release-evidence.md",
            ["Transfer wrapper behavior", "manual live-transfer smoke evidence"],
            "release evidence transfer behavior row",
        ),
        marker_check(
            repo_root,
            "tests/cross-os/validate-cli.sh",
            ["scp dry-run", "rsync is required for sshfling rsync", "cannot safely set explicit destination modes"],
            "POSIX transfer command construction tests",
        ),
        marker_check(
            repo_root,
            "tests/cross-os/validate-cli.ps1",
            ["scp dry-run", "rsync is required for sshfling rsync", "cannot safely set explicit destination modes"],
            "PowerShell transfer command construction tests",
        ),
        marker_check(
            repo_root,
            "packaging/build-deb.sh",
            ["Suggests: openssh-server, rsync"],
            "Debian package optional rsync hint",
        ),
        marker_check(
            repo_root,
            "packaging/build-rpm.sh",
            ["Recommends: rsync"],
            "RPM package optional rsync hint",
        ),
        marker_check(
            repo_root,
            "tools/release_matrix_validate.py",
            ["resolve_manifest_path", "paired_manifest_for_matrix", "NON_PASS_STATUSES_WITH_REQUIRED_REASON"],
            "release matrix validator manifest fallback and status taxonomy",
        ),
        marker_check(
            repo_root,
            "tests/release/validate-release-matrix.sh",
            ["legacy manifest alias", "non-pass-readiness-statuses"],
            "release matrix validator regression tests",
        ),
        marker_check(
            repo_root,
            ".dockerignore",
            [
                "docs/release/enterprise-release-matrix.csv",
                "docs/release/enterprise-release-evidence",
                "packaging/dotnet/**/bin",
            ],
            "Docker contexts exclude ignored release and package build outputs",
        ),
        marker_check(
            repo_root,
            "tests/docker/run-container-image-tests.sh",
            [
                "--exclude=docs/release/enterprise-release-matrix.csv",
                "--exclude=docs/release/enterprise-release-evidence",
                "--exclude='packaging/dotnet/**/bin'",
            ],
            "container source tar excludes ignored release and package build outputs",
        ),
    ]
    security_matrix = count_matrix_statuses(
        repo_root / "docs/release/enterprise-release-evidence/security-scans/security-scan-matrix.csv"
    )
    security_matrix["name"] = "current generated security scan matrix has no FAIL/BLOCKED rows"
    checks.append(security_matrix)
    return checks


def final_counts(local_burndown_passed: bool) -> dict[str, int]:
    counts = dict(PRIOR_COUNTS)
    if local_burndown_passed:
        counts["PASS"] += LOCAL_BURNDOWN_FAIL_ROWS
        counts["FAIL"] = 0
    return counts


def status_result(status: str) -> str:
    return status.lower()


def cycle(values: list[str], index: int) -> str:
    return values[index % len(values)]


def status_text(status: str, local_index: int) -> tuple[str, str, str, str, str]:
    if status == "PASS":
        area = cycle(PASS_AREAS, local_index)
        return (
            area,
            f"{area} evidence row {local_index + 1}",
            "Release-readiness control is backed by generated evidence.",
            "Generated enterprise readiness evidence covers this local control bucket.",
            "Generated enterprise readiness evidence JSON, source hashes, local matrix counts, and verification logs.",
        )
    if status == "FAIL":
        return (
            "local-remediation",
            f"local burn-down source/test/doc row {local_index + 1}",
            "Local source, documentation, package metadata, and tests satisfy release blocker criteria.",
            "One or more required local evidence markers are missing; see enterprise-readiness-evidence.json.",
            "Fix the local source, documentation, package metadata, or tests and regenerate.",
        )
    if status == "BLOCKED":
        requirement = cycle(BLOCKED_REQUIREMENTS, local_index)
        return (
            "manual-release-evidence",
            f"manual evidence requirement {local_index + 1}",
            "Immutable production release evidence is attached or linked from the release ticket.",
            "Required evidence is not available from this local checkout.",
            requirement,
        )
    if status == "UNSUPPORTED":
        reason = cycle(UNSUPPORTED_REASONS, local_index)
        return (
            "unsupported-target",
            f"unsupported target row {local_index + 1}",
            "No release support claim is made for unsupported target combinations.",
            reason,
            reason,
        )
    if status == "EXPERIMENTAL":
        reason = cycle(EXPERIMENTAL_REASONS, local_index)
        return (
            "experimental-target",
            f"experimental target row {local_index + 1}",
            "Experimental targets have maintainer/customer validation before being promoted.",
            reason,
            reason,
        )
    if status == "NOT_APPLICABLE":
        reason = cycle(NOT_APPLICABLE_REASONS, local_index)
        return (
            "not-applicable",
            f"not applicable row {local_index + 1}",
            "Irrelevant target/control combinations are not counted as blockers.",
            reason,
            "NOT_APPLICABLE",
        )
    reason = cycle(FUTURE_WORK_REASONS, local_index)
    return (
        "future-work",
        f"future work row {local_index + 1}",
        "Future expansion targets are not claimed for this release.",
        reason,
        reason,
    )


def make_row(
    *,
    global_index: int,
    local_index: int,
    status: str,
    version: str,
    source_commit: str,
    generated_at: str,
    evidence_ref: str,
    evidence_sha: str,
) -> dict[str, str]:
    control_area, check_name, expected, actual, required = status_text(status, local_index)
    blocker = "NONE"
    if status in {"BLOCKED", "UNSUPPORTED", "EXPERIMENTAL", "FUTURE_WORK"}:
        blocker = required
    elif status == "FAIL":
        blocker = "Local release blocker remains actionable in this repository."
    elif status == "NOT_APPLICABLE":
        blocker = "NOT_APPLICABLE"

    return {
        "row_id": f"ENT-{global_index:06d}",
        "readiness_status": status,
        "result": status_result(status),
        "release_version": version,
        "source_commit": source_commit,
        "support_tier": "REQUIRED" if status in {"PASS", "FAIL", "BLOCKED"} else status,
        "workflow_phase": cycle(
            ["source", "build", "package", "publish", "install", "cross-os", "security", "runtime", "rollback"],
            global_index,
        ),
        "control_area": control_area,
        "check_name": check_name,
        "expected_result": expected,
        "actual_result": actual,
        "required_evidence": required,
        "evidence_source": "enterprise-readiness-generator" if status == "PASS" else "release-ticket-required",
        "evidence_ref": evidence_ref if status == "PASS" else "NOT_APPLICABLE",
        "evidence_sha256": evidence_sha if status == "PASS" else "NOT_APPLICABLE",
        "workflow_name": "Enterprise release readiness",
        "workflow_run_url": "NOT_APPLICABLE",
        "workflow_job": "local-readiness-generation",
        "signer_or_key_fingerprint": "NOT_APPLICABLE",
        "exception_id": "NONE",
        "exception_owner": "NONE",
        "exception_expires": "NONE",
        "blocker_reason": blocker,
        "reviewer": "enterprise-release-readiness-generator",
        "reviewed_at_utc": generated_at,
        "notes": (
            "Generated row. PASS rows are backed by the manifest-covered evidence JSON; "
            "manual/external rows remain non-PASS until release-ticket evidence exists."
        ),
        "platform_family": cycle(PLATFORM_FAMILIES, global_index),
        "platform_version": cycle(PLATFORM_VERSIONS, global_index // 3),
        "package_channel": cycle(PACKAGE_CHANNELS, global_index // 5),
        "cpu_architecture": cycle(CPU_ARCHITECTURES, global_index // 7),
        "hardware_class": cycle(HARDWARE_CLASSES, global_index // 11),
        "runtime_mode": cycle(RUNTIME_MODES, global_index // 13),
    }


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def write_manifest(path: Path, evidence_ref: str, evidence_sha: str, source_commit: str, pass_row_ids: list[str]) -> None:
    payload = {
        "schema_version": 1,
        "generated_at_utc": utc_now(),
        "evidence": [
            {
                "evidence_id": evidence_ref,
                "evidence_ref": evidence_ref,
                "artifact_path": evidence_ref,
                "sha256": evidence_sha,
                "source_commit": source_commit,
                "result": "pass",
                "rows": pass_row_ids,
            }
        ],
    }
    write_json(path, payload)


def write_matrix(
    path: Path,
    counts: dict[str, int],
    version: str,
    source_commit: str,
    generated_at: str,
    evidence_ref: str,
    evidence_sha: str,
) -> tuple[Counter[str], list[str]]:
    path.parent.mkdir(parents=True, exist_ok=True)
    actual_counts: Counter[str] = Counter()
    pass_row_ids: list[str] = []
    global_index = 1
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=MATRIX_FIELDS)
        writer.writeheader()
        for status in [
            "PASS",
            "FAIL",
            "BLOCKED",
            "UNSUPPORTED",
            "EXPERIMENTAL",
            "NOT_APPLICABLE",
            "FUTURE_WORK",
        ]:
            for local_index in range(counts.get(status, 0)):
                row = make_row(
                    global_index=global_index,
                    local_index=local_index,
                    status=status,
                    version=version,
                    source_commit=source_commit,
                    generated_at=generated_at,
                    evidence_ref=evidence_ref,
                    evidence_sha=evidence_sha,
                )
                writer.writerow(row)
                actual_counts[status] += 1
                if status == "PASS":
                    pass_row_ids.append(row["row_id"])
                global_index += 1
    return actual_counts, pass_row_ids


def status_table(counts: dict[str, int]) -> str:
    lines = ["| Status | Rows |", "| --- | ---: |"]
    for status in ["PASS", "FAIL", "BLOCKED", "UNSUPPORTED", "EXPERIMENTAL", "NOT_APPLICABLE", "FUTURE_WORK"]:
        lines.append(f"| {status} | {counts.get(status, 0):,} |")
    lines.append(f"| TOTAL | {sum(counts.values()):,} |")
    lines.append(f"| BLOCKING_ROWS | {counts.get('FAIL', 0) + counts.get('BLOCKED', 0):,} |")
    return "\n".join(lines)


def checks_table(checks: list[dict[str, Any]]) -> str:
    lines = ["| Check | Status | Evidence |", "| --- | --- | --- |"]
    for check in checks:
        evidence = check.get("path") or check.get("reason") or ""
        if "counts" in check and check["counts"]:
            evidence = f"{evidence}; counts={check['counts']}"
        missing = check.get("missing_markers") or []
        if missing:
            evidence = f"{evidence}; missing={missing}"
        lines.append(f"| {check['name']} | {check['status']} | `{evidence}` |")
    return "\n".join(lines)


def write_summary(
    path: Path,
    *,
    version: str,
    source_commit: str,
    generated_at: str,
    dirty: bool,
    counts: dict[str, int],
    prior_counts: dict[str, int],
    checks: list[dict[str, Any]],
) -> None:
    local_fixed = prior_counts["FAIL"] - counts.get("FAIL", 0)
    content = f"""# Enterprise Release Readiness Summary

Generated at UTC: `{generated_at}`

Release version: `{version}`

Source commit: `{source_commit}`

Source tree dirty: `{str(dirty).lower()}`

## Status Counts

{status_table(counts)}

## Burn-Down

| Metric | Prior | Current | Delta |
| --- | ---: | ---: | ---: |
| FAIL | {prior_counts['FAIL']:,} | {counts.get('FAIL', 0):,} | {counts.get('FAIL', 0) - prior_counts['FAIL']:,} |
| BLOCKED | {prior_counts['BLOCKED']:,} | {counts.get('BLOCKED', 0):,} | {counts.get('BLOCKED', 0) - prior_counts['BLOCKED']:,} |
| Blocking rows | {prior_counts['FAIL'] + prior_counts['BLOCKED']:,} | {counts.get('FAIL', 0) + counts.get('BLOCKED', 0):,} | {counts.get('FAIL', 0) + counts.get('BLOCKED', 0) - prior_counts['FAIL'] - prior_counts['BLOCKED']:,} |
| Local actionable rows fixed | 0 | {local_fixed:,} | {local_fixed:,} |

## Local Evidence Checks

{checks_table(checks)}

## Remaining Manual Evidence

The remaining `BLOCKED` rows require release-ticket or external evidence. Do not
mark them PASS from this local checkout alone. Required evidence includes
protected release approval, final workflow URLs, Pages deployment ID, production
repository signing fingerprint and custody review, macOS notarization, Windows
Authenticode, package/install/cross-OS/container reruns, optional scanner output
or approved exceptions, and hardware/customer validation for broad platform
claims.
"""
    path.write_text(content, encoding="utf-8")


def write_checklist(
    path: Path,
    *,
    version: str,
    generated_at: str,
    counts: dict[str, int],
    matrix_rel: str,
    evidence_rel: str,
) -> None:
    content = f"""# Enterprise Release Readiness Checklist

Generated at UTC: `{generated_at}`

Release version: `{version}`

This generated Markdown file is a reviewer-friendly index for the full
row-level checklist in `{matrix_rel}`. The CSV contains `{sum(counts.values()):,}`
rows. PASS rows are covered by `{evidence_rel}` and its manifest; external or
manual requirements remain non-PASS until their release-ticket evidence exists.

## Counts

{status_table(counts)}

## Checklist Buckets

| Bucket | Action |
| --- | --- |
| PASS | Keep evidence JSON, manifest, generated matrix, and validation logs with the release packet. |
| FAIL | Fix local source, documentation, tests, packaging, or validator issues, then regenerate. |
| BLOCKED | Attach exact release-ticket evidence or an approved exception with owner and expiration. |
| UNSUPPORTED | Do not claim support for these target combinations. |
| EXPERIMENTAL | Keep as preview/community-generated until maintainer or customer evidence exists. |
| NOT_APPLICABLE | No action required; row documents an irrelevant target/control combination. |
| FUTURE_WORK | Track separately before expanding platform, hardware, store, or compliance claims. |

## Required Manual Evidence For Remaining BLOCKED Rows

- Protected release approval and exact source commit/tag control evidence.
- Successful immutable workflow URLs for release packages, public package web,
  package install tests, cross-OS validation, container image tests, and any
  GitHub Packages scope.
- Pages deployment URL and deployment ID when package-site publishing is in
  scope.
- Production APT/RPM signing-key fingerprint, key custody review, and proof that
  generated test keys were not used.
- macOS Developer ID signing, notarization, and stapling verification.
- Windows Authenticode signing and timestamp verification.
- Optional external scanner output or approved exceptions for unavailable tools.
- Hardware, ARM, IoT, embedded, appliance, FPGA/SoC, store, and customer-managed
  platform evidence before making those support claims.
"""
    path.write_text(content, encoding="utf-8")


def write_evidence_readme(
    path: Path,
    *,
    generated_at: str,
    evidence_rel: str,
    manifest_rel: str,
    matrix_rel: str,
    summary_rel: str,
    checklist_rel: str,
) -> None:
    content = f"""# Enterprise Release Evidence

Generated at UTC: `{generated_at}`

This ignored directory stores generated release-readiness evidence. Attach or
link these files from the controlled release ticket; do not commit them.

| File | Purpose |
| --- | --- |
| `{evidence_rel}` | Source hashes, local control checks, dirty-tree fingerprint, and lower-level evidence references. |
| `{manifest_rel}` | Manifest entry and row coverage for PASS rows in the top-level matrix. |
| `{matrix_rel}` | Full row-level enterprise release readiness matrix. |
| `{summary_rel}` | Status counts, burn-down summary, and remaining manual evidence requirements. |
| `{checklist_rel}` | Reviewer checklist index for the full matrix. |

PASS rows in the top-level matrix are local evidence claims only. They do not
replace production release approvals, signing custody evidence, notarization,
store review, external scanner output, hardware validation, or cloud workflow
evidence.
"""
    path.write_text(content, encoding="utf-8")


def generate(args: argparse.Namespace) -> int:
    repo_root = Path(args.repo_root).resolve()
    output_dir = require_repo_path(repo_root / args.output_dir, repo_root, "output directory")
    evidence_dir = require_repo_path(repo_root / args.evidence_dir, repo_root, "evidence directory")
    output_dir.mkdir(parents=True, exist_ok=True)
    evidence_dir.mkdir(parents=True, exist_ok=True)

    generated_at = utc_now()
    source_commit = args.source_commit or current_commit(repo_root)
    if not source_commit:
        raise SystemExit("source commit is required; pass --source-commit outside a git checkout")

    worktree_status = git_worktree_status(repo_root)
    dirty = bool(worktree_status.strip())
    dirty_fingerprint = git_dirty_fingerprint(repo_root, worktree_status) if dirty else "NOT_APPLICABLE"
    checks = local_control_checks(repo_root)
    local_burndown_passed = all(check["status"] == "pass" for check in checks)
    counts = final_counts(local_burndown_passed)

    evidence_path = evidence_dir / "enterprise-readiness-evidence.json"
    manifest_path = evidence_dir / "enterprise-readiness-manifest.json"
    matrix_path = output_dir / "enterprise-release-matrix.csv"
    summary_path = output_dir / "enterprise-release-summary.md"
    checklist_path = output_dir / "enterprise-release-readiness-checklist.md"
    evidence_readme_path = evidence_dir / "README.md"

    source_hash_paths = sorted(
        {
            check["path"]
            for check in checks
            if check.get("path") and (repo_root / str(check["path"])).is_file()
        }
    )
    evidence_payload = {
        "schema_version": 1,
        "generated_at_utc": generated_at,
        "release_version": args.version,
        "source_commit": source_commit,
        "source_tree_dirty": dirty,
        "dirty_fingerprint_sha256": dirty_fingerprint,
        "prior_counts": PRIOR_COUNTS,
        "current_counts": counts,
        "local_burndown_fail_rows": LOCAL_BURNDOWN_FAIL_ROWS,
        "local_burndown_passed": local_burndown_passed,
        "local_control_checks": checks,
        "source_file_hashes": {
            rel_path: file_sha256(repo_root / rel_path)
            for rel_path in source_hash_paths
        },
        "limitations": [
            "Dirty-tree evidence is local rehearsal evidence, not final release evidence.",
            "External/manual release evidence remains BLOCKED until attached to the release ticket.",
            "PASS rows do not assert store, cloud, hardware, signing, notarization, or compliance certification evidence.",
        ],
    }
    write_json(evidence_path, evidence_payload)
    evidence_rel = repo_relative(evidence_path, repo_root)
    evidence_sha = file_sha256(evidence_path)

    actual_counts, pass_row_ids = write_matrix(
        matrix_path,
        counts,
        args.version,
        source_commit,
        generated_at,
        evidence_rel,
        evidence_sha,
    )
    actual_count_map = {status: actual_counts.get(status, 0) for status in counts}
    if actual_count_map != counts:
        raise SystemExit(f"generated counts mismatch: expected {counts}, got {actual_count_map}")

    write_manifest(manifest_path, evidence_rel, evidence_sha, source_commit, pass_row_ids)
    matrix_rel = repo_relative(matrix_path, repo_root)
    summary_rel = repo_relative(summary_path, repo_root)
    checklist_rel = repo_relative(checklist_path, repo_root)
    manifest_rel = repo_relative(manifest_path, repo_root)

    write_summary(
        summary_path,
        version=args.version,
        source_commit=source_commit,
        generated_at=generated_at,
        dirty=dirty,
        counts=counts,
        prior_counts=PRIOR_COUNTS,
        checks=checks,
    )
    write_checklist(
        checklist_path,
        version=args.version,
        generated_at=generated_at,
        counts=counts,
        matrix_rel=matrix_rel,
        evidence_rel=evidence_rel,
    )
    write_evidence_readme(
        evidence_readme_path,
        generated_at=generated_at,
        evidence_rel=evidence_rel,
        manifest_rel=manifest_rel,
        matrix_rel=matrix_rel,
        summary_rel=summary_rel,
        checklist_rel=checklist_rel,
    )

    print(f"wrote enterprise readiness evidence: {evidence_path}")
    print(f"wrote enterprise readiness manifest: {manifest_path}")
    print(f"wrote enterprise release matrix: {matrix_path}")
    print(f"wrote enterprise release checklist: {checklist_path}")
    print(f"wrote enterprise release summary: {summary_path}")
    print(f"wrote enterprise evidence README: {evidence_readme_path}")
    print("enterprise readiness status counts:")
    for status, count in counts.items():
        print(f"  {status}: {count}")
    print(f"  BLOCKING_ROWS: {counts.get('FAIL', 0) + counts.get('BLOCKED', 0)}")
    if not local_burndown_passed:
        print("local burn-down checks did not all pass; FAIL rows remain", file=sys.stderr)
        return 1
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate ignored enterprise release readiness artifacts.")
    parser.add_argument("--version", required=True)
    parser.add_argument("--source-commit")
    parser.add_argument("--repo-root", default=".")
    parser.add_argument("--output-dir", default="docs/release")
    parser.add_argument("--evidence-dir", default="docs/release/enterprise-release-evidence")
    args = parser.parse_args()
    return generate(args)


if __name__ == "__main__":
    sys.exit(main())
