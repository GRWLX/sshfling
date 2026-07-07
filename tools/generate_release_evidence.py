#!/usr/bin/env python3
"""Generate release evidence from built package artifacts.

This is intentionally artifact-driven: a release job must build or download the
packages first, then this script records hashes for the exact files being
published and emits a matrix/manifest pair that release_matrix_validate.py can
verify.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
import subprocess
import sys
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
]
GITHUB_OWNER_RE = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$")


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def is_truthy(value: str | None) -> bool:
    return str(value or "").strip().lower() in {"1", "true", "yes", "on"}


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


def repo_relative(path: Path, repo_root: Path) -> str:
    resolved = path.resolve()
    try:
        return resolved.relative_to(repo_root.resolve()).as_posix()
    except ValueError as exc:
        raise SystemExit(f"release evidence path must stay inside repo: {path}") from exc


def require_repo_path(path: Path, repo_root: Path, label: str) -> Path:
    resolved = path.resolve()
    try:
        resolved.relative_to(repo_root.resolve())
    except ValueError as exc:
        raise SystemExit(f"{label} must stay inside repo: {path}") from exc
    return resolved


def require_path_token(name: str, value: str) -> None:
    if not value:
        raise SystemExit(f"{name} is required")
    if any(marker in value for marker in ("/", "\\", "\x00")):
        raise SystemExit(f"{name} must not contain path separators")


def require_owner_token(owner: str) -> None:
    require_path_token("owner", owner)
    if not GITHUB_OWNER_RE.fullmatch(owner):
        raise SystemExit("owner must be a valid GitHub account or organization name")


def reject_symlink_component(root: Path, rel_path: str, label: str) -> None:
    current = root
    for part in Path(rel_path).parts:
        if part in {"", "."}:
            continue
        current = current / part
        if current.is_symlink():
            raise SystemExit(f"{label} path must not use symlinks: {rel_path}")


def require_under_root(root: Path, rel_path: str) -> Path:
    reject_symlink_component(root, rel_path, "required artifact")
    path = (root / rel_path).resolve()
    try:
        path.relative_to(root.resolve())
    except ValueError as exc:
        raise SystemExit(f"required path escapes artifact root: {rel_path}") from exc
    return path


def require_files(root: Path, rel_paths: list[str], label: str) -> None:
    missing: list[str] = []
    for rel_path in rel_paths:
        if not require_under_root(root, rel_path).is_file():
            missing.append(rel_path)
    if missing:
        joined = "\n  - ".join(missing)
        raise SystemExit(f"missing required {label} files:\n  - {joined}")


def collect_files(root: Path) -> list[Path]:
    if not root.is_dir():
        raise SystemExit(f"artifact directory not found: {root}")
    files: list[Path] = []
    for path in sorted(root.rglob("*")):
        rel_path = path.relative_to(root).as_posix()
        if path.is_symlink():
            raise SystemExit(f"artifact path must not be a symlink: {rel_path}")
        if path.is_file():
            files.append(path)
    return files


def release_asset_requirements(version: str) -> list[str]:
    return [
        f"sshfling_{version}_all.deb",
        f"sshfling-{version}-1.noarch.rpm",
        f"sshfling-{version}.tar.gz",
        f"SSHFling.Tool.{version}.nupkg",
        f"sshfling-{version}.pkg",
        f"sshfling-{version}.msi",
        f"sshfling-{version}-windows.zip",
        "SHA256SUMS",
        "RELEASE-EVIDENCE.md",
    ]


def package_site_requirements(version: str, owner: str, require_repo_signatures: bool, public_dir: Path) -> list[str]:
    base = [
        ".nojekyll",
        "index.html",
        "install.sh",
        "community.html",
        "apt/Packages.gz",
        "apt/Packages",
        "apt/Release",
        "apt/SHA256SUMS",
        f"apt/sshfling_{version}_all.deb",
        f"rpm/sshfling-{version}-1.noarch.rpm",
        "rpm/repodata/repomd.xml",
        "rpm/SHA256SUMS",
        "homebrew/sshfling.rb",
        "macos/install-pkg.sh",
        "macos/uninstall-pkg.sh",
        "windows/install.ps1",
        "windows/uninstall.ps1",
        "downloads/SHA256SUMS",
        "downloads/index.html",
        f"downloads/sshfling-{version}.tar.gz",
        f"downloads/SSHFling.Tool.{version}.nupkg",
        f"downloads/sshfling-{version}.pkg",
        f"downloads/sshfling-{version}.msi",
        f"downloads/sshfling-{version}-windows.zip",
        "arch/PKGBUILD",
        "arch/.SRCINFO",
        "alpine/APKBUILD",
        "freebsd/security/sshfling/Makefile",
        "freebsd/security/sshfling/distinfo",
        "freebsd/security/sshfling/pkg-descr",
        "openbsd/security/sshfling/Makefile",
        "openbsd/security/sshfling/distinfo",
        "openbsd/security/sshfling/pkg/DESCR",
        "pkgsrc/security/sshfling/Makefile",
        "pkgsrc/security/sshfling/DESCR",
        "pkgsrc/security/sshfling/PLIST",
        "pkgsrc/security/sshfling/distinfo",
        "nix/flake.nix",
        "guix/sshfling.scm",
        "void/template",
        f"gentoo/app-admin/sshfling/sshfling-{version}.ebuild",
        "slackware/sshfling.SlackBuild",
        "slackware/slack-desc",
        "opensuse/sshfling.spec",
        "snap/snapcraft.yaml",
        "termux/packages/sshfling/build.sh",
        "appimage/AppImageBuilder.yml",
        "scoop/sshfling.json",
        f"winget/manifests/g/{owner}/SSHFling/{version}/{owner}.SSHFling.yaml",
        f"winget/manifests/g/{owner}/SSHFling/{version}/{owner}.SSHFling.locale.en-US.yaml",
        f"winget/manifests/g/{owner}/SSHFling/{version}/{owner}.SSHFling.installer.yaml",
        "chocolatey/sshfling.nuspec",
        "chocolatey/tools/chocolateyinstall.ps1",
        f"chocolatey/sshfling.{version}.nupkg",
        "chocolatey/install.ps1",
        "RELEASE-EVIDENCE.md",
    ]
    signed_files = [
        "sshfling-repo.gpg",
        "sshfling-repo.asc",
        "sshfling-repo-fingerprint.txt",
        "apt/InRelease",
        "apt/Release.gpg",
        "rpm/repodata/repomd.xml.asc",
    ]
    if require_repo_signatures or any((public_dir / rel_path).exists() for rel_path in signed_files):
        base.extend(signed_files)
    return base


def detect_owner(args_owner: str | None) -> str:
    owner = args_owner or os.environ.get("OWNER") or os.environ.get("GITHUB_REPOSITORY_OWNER")
    if owner:
        return owner
    repository = os.environ.get("REPOSITORY") or os.environ.get("GITHUB_REPOSITORY")
    if repository and "/" in repository:
        return repository.split("/", 1)[0]
    return ""


def fingerprint_from_site(public_dir: Path) -> str:
    path = public_dir / "sshfling-repo-fingerprint.txt"
    if not path.is_file():
        return "NOT_APPLICABLE"
    return "".join(path.read_text(encoding="utf-8").split()).upper() or "NOT_APPLICABLE"


def artifact_records(root: Path, files: list[Path], repo_root: Path) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    root_resolved = root.resolve()
    for index, path in enumerate(files, 1):
        try:
            rel_to_root = path.resolve().relative_to(root_resolved).as_posix()
        except ValueError as exc:
            raise SystemExit(f"artifact path escapes artifact root: {path}") from exc
        stat = path.stat()
        records.append(
            {
                "row_id": f"RG-{index:05d}",
                "path": repo_relative(path, repo_root),
                "relative_path": rel_to_root,
                "bytes": stat.st_size,
                "sha256": file_sha256(path),
                "mode": oct(stat.st_mode & 0o777),
            }
        )
    return records


def workflow_run_url() -> str:
    server_url = os.environ.get("GITHUB_SERVER_URL")
    repository = os.environ.get("GITHUB_REPOSITORY")
    run_id = os.environ.get("GITHUB_RUN_ID")
    if server_url and repository and run_id:
        return f"{server_url}/{repository}/actions/runs/{run_id}"
    return "NOT_APPLICABLE"


def make_rows(
    *,
    mode: str,
    version: str,
    source_commit: str,
    generated_at: str,
    evidence_ref: str,
    evidence_sha: str,
    artifacts: list[dict[str, Any]],
    signer_fingerprint: str,
) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    phase = "github_release_assets" if mode == "release-assets" else "public_package_site"
    workflow_name = os.environ.get("GITHUB_WORKFLOW") or (
        "Release packages without web" if mode == "release-assets" else "Release packages with public web"
    )
    workflow_job = os.environ.get("GITHUB_JOB") or phase
    for record in artifacts:
        actual = (
            f"{record['relative_path']} exists with bytes={record['bytes']} "
            f"and sha256={record['sha256']} in generated release evidence."
        )
        rows.append(
            {
                "row_id": str(record["row_id"]),
                "readiness_status": "PASS",
                "result": "pass",
                "release_version": version,
                "source_commit": source_commit,
                "support_tier": "REQUIRED",
                "workflow_phase": phase,
                "control_area": "artifact_integrity",
                "check_name": f"{mode}:{record['relative_path']}",
                "expected_result": "Published artifact exists and has immutable bytes/hash evidence.",
                "actual_result": actual,
                "required_evidence": "Generated evidence JSON, release matrix, manifest, and workflow provenance.",
                "evidence_source": "generated-artifact-hash",
                "evidence_ref": evidence_ref,
                "evidence_sha256": evidence_sha,
                "workflow_name": workflow_name,
                "workflow_run_url": workflow_run_url(),
                "workflow_job": workflow_job,
                "signer_or_key_fingerprint": signer_fingerprint,
                "exception_id": "NONE",
                "exception_owner": "NONE",
                "exception_expires": "NONE",
                "blocker_reason": "NONE",
                "reviewer": "release-evidence-generator",
                "reviewed_at_utc": generated_at,
                "notes": "Generated after package artifacts were built or downloaded.",
            }
        )
    return rows


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def write_matrix(path: Path, rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=MATRIX_FIELDS)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def generate(args: argparse.Namespace) -> int:
    repo_root = Path(args.repo_root).resolve()
    require_path_token("version", args.version)
    output_dir = require_repo_path(repo_root / args.output_dir, repo_root, "output directory")
    output_dir.mkdir(parents=True, exist_ok=True)

    source_commit = args.source_commit or os.environ.get("GITHUB_SHA") or current_commit(repo_root)
    if not source_commit:
        raise SystemExit("source commit is required; pass --source-commit outside a git checkout")

    require_repo_signatures = args.require_repo_signatures or is_truthy(os.environ.get("REQUIRE_REPO_SIGNATURES"))
    owner = detect_owner(args.owner)
    if args.mode == "package-site" and not owner:
        raise SystemExit("package-site evidence requires --owner, OWNER, GITHUB_REPOSITORY_OWNER, or REPOSITORY")
    if args.mode == "package-site":
        require_owner_token(owner)

    if args.mode == "release-assets":
        artifact_root = require_repo_path(repo_root / args.artifacts_dir, repo_root, "artifact directory")
        required = release_asset_requirements(args.version)
        signer_fingerprint = "NOT_APPLICABLE"
    else:
        artifact_root = require_repo_path(repo_root / args.public_dir, repo_root, "public directory")
        required = package_site_requirements(args.version, owner, require_repo_signatures, artifact_root)
        signer_fingerprint = fingerprint_from_site(artifact_root)

    require_files(artifact_root, required, args.mode)
    files = collect_files(artifact_root)
    if not files:
        raise SystemExit(f"no artifact files found under {artifact_root}")

    generated_at = utc_now()
    evidence_path = output_dir / f"{args.mode}-evidence.json"
    manifest_path = output_dir / f"{args.mode}-manifest.json"
    matrix_path = output_dir / f"{args.mode}-matrix.csv"
    artifacts = artifact_records(artifact_root, files, repo_root)
    row_ids = [str(record["row_id"]) for record in artifacts]

    evidence_payload: dict[str, Any] = {
        "schema_version": 1,
        "mode": args.mode,
        "release_version": args.version,
        "source_commit": source_commit,
        "generated_at_utc": generated_at,
        "artifact_root": repo_relative(artifact_root, repo_root),
        "required_files": required,
        "rows": row_ids,
        "artifacts": artifacts,
    }
    if signer_fingerprint != "NOT_APPLICABLE":
        evidence_payload["signer_or_key_fingerprint"] = signer_fingerprint
    write_json(evidence_path, evidence_payload)

    evidence_ref = repo_relative(evidence_path, repo_root)
    evidence_sha = file_sha256(evidence_path)
    manifest_payload = {
        "schema_version": 1,
        "generated_at_utc": generated_at,
        "evidence": [
            {
                "evidence_id": evidence_ref,
                "evidence_ref": evidence_ref,
                "artifact_path": evidence_ref,
                "sha256": evidence_sha,
                "source_commit": source_commit,
                "result": "pass",
                "mode": args.mode,
                "release_version": args.version,
                "rows": row_ids,
            }
        ],
    }
    write_json(manifest_path, manifest_payload)

    rows = make_rows(
        mode=args.mode,
        version=args.version,
        source_commit=source_commit,
        generated_at=generated_at,
        evidence_ref=evidence_ref,
        evidence_sha=evidence_sha,
        artifacts=artifacts,
        signer_fingerprint=signer_fingerprint,
    )
    write_matrix(matrix_path, rows)

    print(f"wrote release evidence: {evidence_path}")
    print(f"wrote release manifest: {manifest_path}")
    print(f"wrote release matrix: {matrix_path}")
    print(f"release evidence rows: {len(rows)}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate release evidence from built package artifacts.")
    parser.add_argument("--mode", choices=["release-assets", "package-site"], required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--source-commit")
    parser.add_argument("--repo-root", default=".")
    parser.add_argument("--output-dir", default="docs/release/enterprise-release-evidence/generated")
    parser.add_argument("--artifacts-dir", default="release-dist")
    parser.add_argument("--public-dir", default="public")
    parser.add_argument("--owner")
    parser.add_argument("--require-repo-signatures", action="store_true")
    args = parser.parse_args()
    return generate(args)


if __name__ == "__main__":
    sys.exit(main())
