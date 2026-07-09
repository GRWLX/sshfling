#!/usr/bin/env python3
"""Generate release security, SBOM, license, and dependency evidence.

The baseline checks intentionally use only the Python standard library so the
release evidence hook works in a minimal checkout. Optional external scanners
can be enabled when a release runner has them installed.
"""

from __future__ import annotations

import argparse
import ast
import csv
import hashlib
import json
import math
import os
import re
import shlex
import shutil
import subprocess
import sys
import uuid
import xml.etree.ElementTree as ET
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

EXCLUDED_DIRS = {
    ".git",
    ".venv",
    "__pycache__",
    ".pytest_cache",
    ".mypy_cache",
    "build",
    "dist",
    "public",
    "package-dist",
    "release-dist",
}
OPTIONAL_SCANNER_EXCLUDED_PATHS = [
    ".git",
    "build",
    "dist",
    "public",
    "package-dist",
    "release-dist",
    "docs/release/enterprise-release-matrix.csv",
    "docs/release/enterprise-release-readiness-checklist.md",
    "docs/release/enterprise-release-summary.md",
    "docs/release/enterprise-release-evidence",
    "packaging/dotnet/SSHFling.Tool/bin",
    "packaging/dotnet/SSHFling.Tool/obj",
    "packaging/java/target",
]


def optional_scanner_exclusions(repo_root: Path) -> tuple[list[str], list[str]]:
    dirs: list[str] = []
    files: list[str] = []
    for path_text in OPTIONAL_SCANNER_EXCLUDED_PATHS:
        path = repo_root / path_text
        if path.is_file() or (not path.exists() and Path(path_text).suffix):
            files.append(path_text)
        else:
            dirs.append(path_text)
    return dirs, files


TEXT_SCAN_MAX_BYTES = 2 * 1024 * 1024

TRIVY_MISCONFIG_ALLOWLIST = {
    (
        "ssh-server/Dockerfile",
        "DS002",
    ): "The SSH daemon container intentionally starts as root so sshd can bind, privilege-separate, and manage the deploy test account.",
    (
        "tests/docker/Dockerfile.production",
        "DS002",
    ): "The production lifecycle test container intentionally runs as root to create, expire, lock, and delete isolated Unix users.",
}

SECRET_PATTERNS = [
    ("private-key", re.compile(r"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----")),
    ("aws-access-key-id", re.compile(r"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b")),
    ("github-token", re.compile(r"\bgh[pousr]_[A-Za-z0-9_]{36,}\b")),
    ("gitlab-token", re.compile(r"\bglpat-[A-Za-z0-9_-]{20,}\b")),
    ("slack-token", re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{20,}\b")),
    ("stripe-secret-key", re.compile(r"\bsk_(?:live|test)_[A-Za-z0-9]{24,}\b")),
    ("npm-token", re.compile(r"\bnpm_[A-Za-z0-9_]{30,}\b")),
    ("pypi-token", re.compile(r"\bpypi-[A-Za-z0-9_-]{40,}\b")),
    ("credential-url", re.compile(r"\b[a-z][a-z0-9+.-]*://[^/\s:@]+:[^/\s:@]{8,}@[^/\s]+", re.IGNORECASE)),
]

SECRET_ASSIGNMENT_RE = re.compile(
    r"""
    (?P<name>
        [A-Za-z_][A-Za-z0-9_.-]*
        (?:
            password|passwd|pwd|secret|token|api[_-]?key|access[_-]?key|
            private[_-]?key|client[_-]?secret|session[_-]?secret
        )
        [A-Za-z0-9_.-]*
    )
    \s*[:=]\s*
    (?P<quote>['"]?)
    (?P<value>[A-Za-z0-9_./+=:@%!-]{20,})
    (?P=quote)
    """,
    re.IGNORECASE | re.VERBOSE,
)

PLACEHOLDER_SECRET_MARKERS = {
    "changeme",
    "changeit",
    "dummy",
    "example",
    "fake",
    "placeholder",
    "replace",
    "sample",
    "your",
}

LICENSE_EXPECTATIONS = [
    {
        "name": "root commercial license",
        "path": "LICENSE",
        "contains": ["SSHFling Commercial License", "proprietary"],
    },
    {
        "name": "README license pointer",
        "path": "README.md",
        "contains": ["## License", "written commercial license", "LICENSE"],
    },
    {
        "name": "Nix unfree license marker",
        "path": "flake.nix",
        "contains": ["license = licenses.unfree;"],
    },
    {
        "name": "RPM license reference",
        "path": "packaging/build-rpm.sh",
        "contains": ["License: LicenseRef-SSHFling-Commercial"],
    },
    {
        "name": "community package license references",
        "path": "packaging/build-community-manifests.sh",
        "contains": ["LicenseRef-SSHFling-Commercial", "Proprietary", "SSHFling Commercial License"],
    },
    {
        "name": "public package license verification",
        "path": "packaging/verify-public-web.sh",
        "contains": ["license :cannot_represent", "LicenseRef-SSHFling-Commercial", "requireLicenseAcceptance"],
    },
]

SYSTEMD_HARDENING_KEYS = [
    "User",
    "Group",
    "UMask",
    "StateDirectory",
    "RuntimeDirectory",
    "NoNewPrivileges",
    "PrivateTmp",
    "PrivateDevices",
    "ProtectSystem",
    "ProtectHome",
    "ProtectClock",
    "ProtectKernelTunables",
    "ProtectKernelModules",
    "ProtectKernelLogs",
    "ProtectControlGroups",
    "CapabilityBoundingSet",
    "AmbientCapabilities",
    "LockPersonality",
    "MemoryDenyWriteExecute",
    "RestrictRealtime",
    "RestrictSUIDSGID",
    "RestrictNamespaces",
    "RestrictAddressFamilies",
    "SystemCallArchitectures",
    "SystemCallFilter",
]

KEY_CUSTODY_EXPECTATIONS = [
    {
        "name": "issuer service runs with dedicated unprivileged identity",
        "path": "systemd/sshflingd.service",
        "markers": ["User=sshflingd", "Group=sshflingd", "NoNewPrivileges=true"],
    },
    {
        "name": "issuer service cannot write local key and policy directory",
        "path": "systemd/sshflingd.service",
        "markers": ["ProtectSystem=strict", "ReadOnlyPaths=/etc/sshfling", "UMask=0077"],
    },
    {
        "name": "issuer environment file documents root-owned group-readable custody",
        "path": "systemd/sshflingd.env.example",
        "markers": ["owner root, group sshflingd, mode 0640", "SSHFLING_CA_KEY=/etc/sshfling/ca_user_ed25519"],
    },
    {
        "name": "Debian package preserves root custody for issuer config",
        "path": "packaging/build-deb.sh",
        "markers": [
            "ensure_package_dir /etc/sshfling 0750 root sshflingd",
            "chown root:sshflingd /etc/sshfling/sshflingd.env",
            "chmod 0640 /etc/sshfling/sshflingd.env",
        ],
    },
    {
        "name": "RPM package preserves root custody for issuer config",
        "path": "packaging/build-rpm.sh",
        "markers": [
            "ensure_package_dir /etc/sshfling 0750 root sshflingd",
            "chown root:sshflingd /etc/sshfling/sshflingd.env",
            "chmod 0640 /etc/sshfling/sshflingd.env",
        ],
    },
    {
        "name": "package site requires stable repository signing material for publish",
        "path": ".github/workflows/public-package-web.yml",
        "markers": [
            "SSHFLING_REPO_GPG_PRIVATE_KEY",
            "SSHFLING_REPO_GPG_FINGERPRINT",
            "Ephemeral repository signing keys are not allowed for package site publishing.",
        ],
    },
    {
        "name": "repository signing key fingerprint is pinned and verified",
        "path": "packaging/build-public-web.sh",
        "markers": [
            "REQUIRE_REPO_SIGNATURES requires SSHFLING_REPO_GPG_PRIVATE_KEY",
            "REQUIRE_REPO_SIGNATURES requires SSHFLING_REPO_GPG_FINGERPRINT",
            "Repository signing key fingerprint mismatch.",
            "sshfling-repo-fingerprint.txt",
        ],
    },
    {
        "name": "published package site verifier rejects missing fingerprint evidence",
        "path": "packaging/verify-public-web.sh",
        "markers": [
            "verify_repo_fingerprint_file",
            "REQUIRE_REPO_SIGNATURES requires SSHFLING_REPO_GPG_FINGERPRINT",
            "repository signing fingerprint mismatch",
        ],
    },
]

KEY_CUSTODY_EXTERNAL_EVIDENCE = [
    "Protected tag or release-environment approval record for the production release.",
    "Production repository signing key owner, storage location, fingerprint, rotation plan, and access-review record.",
    "CA private key storage, owner/group membership review, and rotation or revocation record for production issuer hosts.",
]


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
    digest = hashlib.sha256()
    digest.update(status.encode("utf-8", errors="surrogateescape"))
    for command in (["git", "diff", "--binary"], ["git", "diff", "--cached", "--binary"]):
        try:
            output = subprocess.check_output(command, cwd=repo_root, stderr=subprocess.DEVNULL)
        except (OSError, subprocess.CalledProcessError):
            output = b""
        digest.update(b"\0")
        digest.update(output)
    return digest.hexdigest()


def workflow_run_url() -> str:
    server_url = os.environ.get("GITHUB_SERVER_URL")
    repository = os.environ.get("GITHUB_REPOSITORY")
    run_id = os.environ.get("GITHUB_RUN_ID")
    if server_url and repository and run_id:
        return f"{server_url}/{repository}/actions/runs/{run_id}"
    return "NOT_APPLICABLE"


def repo_relative(path: Path, repo_root: Path) -> str:
    resolved = path.resolve()
    try:
        return resolved.relative_to(repo_root.resolve()).as_posix()
    except ValueError as exc:
        raise SystemExit(f"release evidence path must stay inside repo: {path}") from exc


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def tracked_files(repo_root: Path) -> list[Path]:
    if (repo_root / ".git").exists():
        try:
            output = subprocess.check_output(
                ["git", "ls-files", "-z"],
                cwd=repo_root,
                stderr=subprocess.DEVNULL,
            )
            return sorted(
                repo_root / item.decode("utf-8", errors="surrogateescape")
                for item in output.split(b"\0")
                if item
            )
        except (OSError, subprocess.CalledProcessError):
            pass

    files: list[Path] = []
    for path in repo_root.rglob("*"):
        if not path.is_file():
            continue
        rel_parts = path.relative_to(repo_root).parts
        if any(part in EXCLUDED_DIRS for part in rel_parts):
            continue
        files.append(path)
    return sorted(files)


def logical_lines(path: Path) -> list[str]:
    lines: list[str] = []
    current = ""
    for raw_line in read_text(path).splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.endswith("\\"):
            current += line[:-1] + " "
            continue
        lines.append((current + line).strip())
        current = ""
    if current.strip():
        lines.append(current.strip())
    return lines


def shell_files(files: list[Path], repo_root: Path) -> list[Path]:
    found: list[Path] = []
    for path in files:
        rel = repo_relative(path, repo_root)
        if path.suffix == ".sh" or rel in {"production/sshfling-session"}:
            found.append(path)
            continue
        if path.stat().st_size <= TEXT_SCAN_MAX_BYTES:
            first_line = read_text(path).splitlines()[:1]
            if first_line and re.search(r"\b(?:ba)?sh\b", first_line[0]):
                found.append(path)
    return sorted(set(found))


def python_files(files: list[Path]) -> list[Path]:
    found: list[Path] = []
    for path in files:
        if path.suffix == ".py":
            found.append(path)
            continue
        if path.stat().st_size <= TEXT_SCAN_MAX_BYTES:
            first_line = read_text(path).splitlines()[:1]
            if first_line and "python" in first_line[0]:
                found.append(path)
    return sorted(set(found))


def dockerfiles(files: list[Path]) -> list[Path]:
    return sorted(
        path
        for path in files
        if path.name == "Dockerfile" or path.name.startswith("Dockerfile.") or path.name.endswith(".Dockerfile")
    )


def systemd_units(files: list[Path]) -> list[Path]:
    return sorted(path for path in files if path.suffix == ".service")


def shannon_entropy(value: str) -> float:
    if not value:
        return 0.0
    entropy = 0.0
    for char in set(value):
        probability = value.count(char) / len(value)
        entropy -= probability * math.log2(probability)
    return entropy


def looks_like_placeholder_secret(value: str) -> bool:
    normalized = re.sub(r"[^a-z0-9]+", "", value.lower())
    if not normalized:
        return True
    if any(marker in normalized for marker in PLACEHOLDER_SECRET_MARKERS):
        return True
    if len(normalized) % 2 == 0 and normalized[: len(normalized) // 2] == normalized[len(normalized) // 2 :]:
        return True
    if len(set(normalized)) <= 3:
        return True
    if re.fullmatch(r"(?:x+|0+|1+|a+|abc(?:123)?)+", normalized):
        return True
    return False


def add_secret_finding(
    findings: list[dict[str, Any]],
    *,
    path: Path,
    repo_root: Path,
    line_number: int,
    pattern_name: str,
    matched_value: str,
    identifier: str = "",
) -> None:
    findings.append(
        {
            "path": repo_relative(path, repo_root),
            "line": line_number,
            "pattern": pattern_name,
            "identifier": identifier,
            "match_sha256_12": hashlib.sha256(matched_value.encode("utf-8")).hexdigest()[:12],
        }
    )


def scan_secrets(files: list[Path], repo_root: Path) -> dict[str, Any]:
    findings: list[dict[str, Any]] = []
    scanned = 0
    skipped_large = 0
    for path in files:
        try:
            size = path.stat().st_size
        except OSError:
            continue
        if size > TEXT_SCAN_MAX_BYTES:
            skipped_large += 1
            continue
        text = read_text(path)
        scanned += 1
        for line_number, line in enumerate(text.splitlines(), 1):
            for pattern_name, pattern in SECRET_PATTERNS:
                match = pattern.search(line)
                if not match:
                    continue
                matched_value = match.group(0)
                if looks_like_placeholder_secret(matched_value):
                    continue
                add_secret_finding(
                    findings,
                    path=path,
                    repo_root=repo_root,
                    line_number=line_number,
                    pattern_name=pattern_name,
                    matched_value=matched_value,
                )
            for match in SECRET_ASSIGNMENT_RE.finditer(line):
                value = match.group("value")
                if value.startswith(("/", "./", "../")):
                    continue
                if not match.group("quote") and ("/" in value or "." in value):
                    continue
                if looks_like_placeholder_secret(value):
                    continue
                if shannon_entropy(value) < 3.0:
                    continue
                add_secret_finding(
                    findings,
                    path=path,
                    repo_root=repo_root,
                    line_number=line_number,
                    pattern_name="generic-secret-assignment",
                    matched_value=value,
                    identifier=match.group("name"),
                )
    return {
        "scanner": "builtin-high-confidence-secret-patterns",
        "scanned_files": scanned,
        "skipped_large_files": skipped_large,
        "patterns": [name for name, _pattern in SECRET_PATTERNS] + ["generic-secret-assignment"],
        "findings": findings,
        "status": "pass" if not findings else "fail",
    }


def scan_license(repo_root: Path) -> dict[str, Any]:
    checks: list[dict[str, Any]] = []
    failures: list[dict[str, Any]] = []
    for expectation in LICENSE_EXPECTATIONS:
        rel_path = str(expectation["path"])
        path = repo_root / rel_path
        missing: list[str] = []
        exists = path.is_file()
        text = read_text(path) if exists else ""
        for needle in expectation["contains"]:
            if needle not in text:
                missing.append(needle)
        check = {
            "name": expectation["name"],
            "path": rel_path,
            "status": "pass" if exists and not missing else "fail",
            "missing_markers": missing,
        }
        checks.append(check)
        if check["status"] != "pass":
            failures.append(check)
    return {
        "scanner": "builtin-license-marker-checks",
        "license_id": "LicenseRef-SSHFling-Commercial",
        "license_name": "SSHFling Commercial License",
        "checks": checks,
        "failures": failures,
        "status": "pass" if not failures else "fail",
    }


def iter_logical_shell_lines(path: Path) -> list[tuple[int, str]]:
    logical: list[tuple[int, str]] = []
    current = ""
    start_line = 0
    for line_number, raw_line in enumerate(read_text(path).splitlines(), 1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if not current:
            start_line = line_number
        if line.endswith("\\"):
            current += line[:-1] + " "
            continue
        logical.append((start_line, (current + line).strip()))
        current = ""
    if current.strip():
        logical.append((start_line, current.strip()))
    return logical


def line_hash(line: str) -> str:
    return hashlib.sha256(line.encode("utf-8")).hexdigest()[:12]


def shell_chmod_is_world_writable(command: str) -> bool:
    try:
        tokens = shlex.split(command)
    except ValueError:
        tokens = command.split()
    for index, token in enumerate(tokens[:-1]):
        if Path(token).name != "chmod":
            continue
        mode = tokens[index + 1]
        if re.fullmatch(r"0?[0-7]{3,4}", mode):
            perms = mode[-3:]
            if perms[1] in {"2", "3", "6", "7"} or perms[2] in {"2", "3", "6", "7"}:
                return True
            continue
        if re.search(r"(?:^|[,=])(?:a|o)?\+[^,\s]*w", mode):
            return True
    return False


def add_static_finding(
    findings: list[dict[str, Any]],
    *,
    path: Path,
    repo_root: Path,
    line_number: int,
    rule_id: str,
    message: str,
    severity: str = "high",
    line: str = "",
) -> None:
    findings.append(
        {
            "path": repo_relative(path, repo_root),
            "line": line_number,
            "rule_id": rule_id,
            "severity": severity,
            "message": message,
            "line_sha256_12": line_hash(line),
        }
    )


def scan_shell_static(files: list[Path], repo_root: Path) -> dict[str, Any]:
    findings: list[dict[str, Any]] = []
    scanned = 0
    for path in shell_files(files, repo_root):
        scanned += 1
        for line_number, line in iter_logical_shell_lines(path):
            if re.search(r"(?:curl|wget)\b[^|;\n]*\|\s*(?:sudo\s+)?(?:bash|sh)\b", line):
                add_static_finding(
                    findings,
                    path=path,
                    repo_root=repo_root,
                    line_number=line_number,
                    rule_id="shell-pipe-to-shell",
                    message="Download-to-shell execution must be replaced with download, verify, then execute steps.",
                    line=line,
                )
            if re.search(r"(?:bash|sh)\s+<\s*\(\s*(?:curl|wget)\b", line):
                add_static_finding(
                    findings,
                    path=path,
                    repo_root=repo_root,
                    line_number=line_number,
                    rule_id="shell-process-substitution-download",
                    message="Shell process substitution from a network downloader bypasses artifact verification.",
                    line=line,
                )
            if re.search(r"\b(?:curl|wget)\b.*(?:\s-k\b|--insecure|--no-check-certificate)", line):
                add_static_finding(
                    findings,
                    path=path,
                    repo_root=repo_root,
                    line_number=line_number,
                    rule_id="shell-tls-verification-disabled",
                    message="Downloader disables TLS certificate verification.",
                    line=line,
                )
            if re.search(r"\bmktemp\b(?:\s+[^\s#;&|)]+)*\s-u(?:[\s);]|$)", line):
                add_static_finding(
                    findings,
                    path=path,
                    repo_root=repo_root,
                    line_number=line_number,
                    rule_id="shell-mktemp-dry-run",
                    message="mktemp -u creates a race-prone path without opening it.",
                    line=line,
                )
            if re.search(r"^\s*set\s+-[A-Za-z]*x[A-Za-z]*\b", line):
                add_static_finding(
                    findings,
                    path=path,
                    repo_root=repo_root,
                    line_number=line_number,
                    rule_id="shell-xtrace-enabled",
                    message="set -x can leak secrets into release logs.",
                    severity="medium",
                    line=line,
                )
            if shell_chmod_is_world_writable(line):
                add_static_finding(
                    findings,
                    path=path,
                    repo_root=repo_root,
                    line_number=line_number,
                    rule_id="shell-world-writable-mode",
                    message="World-writable chmod modes should not be used in release or custody scripts.",
                    line=line,
                )
            if re.search(r"\bsshpass\s+-p\s+\S+", line) or re.search(
                r"\bdocker\s+login\b.*(?:\s-p\s+\S+|--password\s+\S+)", line
            ):
                add_static_finding(
                    findings,
                    path=path,
                    repo_root=repo_root,
                    line_number=line_number,
                    rule_id="shell-secret-on-command-line",
                    message="Secrets passed as command-line arguments are exposed through process listings and logs.",
                    line=line,
                )
            if re.search(r"(?:>|>>)\s*/tmp/[A-Za-z0-9_.-]*(?:\$\$|\$RANDOM)", line):
                add_static_finding(
                    findings,
                    path=path,
                    repo_root=repo_root,
                    line_number=line_number,
                    rule_id="shell-predictable-tmp-path",
                    message="Predictable temporary paths should be replaced with mktemp-created files or directories.",
                    line=line,
                )
    return {
        "scanner": "builtin-shell-static-security-rules",
        "scanned_files": scanned,
        "rules": sorted({finding["rule_id"] for finding in findings})
        or [
            "shell-mktemp-dry-run",
            "shell-pipe-to-shell",
            "shell-process-substitution-download",
            "shell-predictable-tmp-path",
            "shell-secret-on-command-line",
            "shell-tls-verification-disabled",
            "shell-world-writable-mode",
            "shell-xtrace-enabled",
        ],
        "findings": findings,
        "status": "pass" if not findings else "fail",
    }


def call_name(node: ast.AST) -> str:
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        parent = call_name(node.value)
        return f"{parent}.{node.attr}" if parent else node.attr
    return ""


def keyword_is_true(node: ast.Call, name: str) -> bool:
    for keyword in node.keywords:
        if keyword.arg == name and isinstance(keyword.value, ast.Constant) and keyword.value.value is True:
            return True
    return False


def keyword_is_false(node: ast.Call, name: str) -> bool:
    for keyword in node.keywords:
        if keyword.arg == name and isinstance(keyword.value, ast.Constant) and keyword.value.value is False:
            return True
    return False


def yaml_loader_is_safe(node: ast.Call) -> bool:
    for keyword in node.keywords:
        if keyword.arg != "Loader":
            continue
        loader = call_name(keyword.value)
        if loader in {"SafeLoader", "CSafeLoader", "yaml.SafeLoader", "yaml.CSafeLoader"}:
            return True
    return False


def scan_python_static(files: list[Path], repo_root: Path) -> dict[str, Any]:
    findings: list[dict[str, Any]] = []
    scanned = 0
    dangerous_deserializers = {"pickle.load", "pickle.loads", "marshal.load", "marshal.loads"}
    process_shell_apis = {
        "subprocess.run",
        "subprocess.call",
        "subprocess.check_call",
        "subprocess.check_output",
        "subprocess.Popen",
    }
    command_execution_apis = {"os.system", "os.popen", "subprocess.getoutput", "subprocess.getstatusoutput"}

    for path in python_files(files):
        scanned += 1
        text = read_text(path)
        try:
            tree = ast.parse(text, filename=repo_relative(path, repo_root))
        except SyntaxError as exc:
            add_static_finding(
                findings,
                path=path,
                repo_root=repo_root,
                line_number=exc.lineno or 1,
                rule_id="python-syntax-error",
                message="Python file could not be parsed for static security checks.",
                line=(exc.text or "").strip(),
            )
            continue

        for node in ast.walk(tree):
            if not isinstance(node, ast.Call):
                continue
            name = call_name(node.func)
            line_number = getattr(node, "lineno", 1)
            if name in {"eval", "exec"}:
                add_static_finding(
                    findings,
                    path=path,
                    repo_root=repo_root,
                    line_number=line_number,
                    rule_id="python-dynamic-code-execution",
                    message="eval/exec should not be used in release or security tooling.",
                )
            if name in command_execution_apis:
                add_static_finding(
                    findings,
                    path=path,
                    repo_root=repo_root,
                    line_number=line_number,
                    rule_id="python-shell-command-api",
                    message="Direct shell command APIs should use argument-vector subprocess calls instead.",
                )
            if name in process_shell_apis and keyword_is_true(node, "shell"):
                add_static_finding(
                    findings,
                    path=path,
                    repo_root=repo_root,
                    line_number=line_number,
                    rule_id="python-subprocess-shell-true",
                    message="subprocess shell=True allows shell injection when command data is variable.",
                )
            if name in dangerous_deserializers:
                add_static_finding(
                    findings,
                    path=path,
                    repo_root=repo_root,
                    line_number=line_number,
                    rule_id="python-unsafe-deserialization",
                    message="Unsafe binary deserialization can execute code when input is attacker-controlled.",
                )
            if name == "tempfile.mktemp":
                add_static_finding(
                    findings,
                    path=path,
                    repo_root=repo_root,
                    line_number=line_number,
                    rule_id="python-insecure-tempfile",
                    message="tempfile.mktemp is race-prone; use NamedTemporaryFile or mkstemp.",
                )
            if name == "yaml.load" and not yaml_loader_is_safe(node):
                add_static_finding(
                    findings,
                    path=path,
                    repo_root=repo_root,
                    line_number=line_number,
                    rule_id="python-unsafe-yaml-load",
                    message="yaml.load requires SafeLoader or CSafeLoader for untrusted input.",
                )
            if name.startswith("requests.") and keyword_is_false(node, "verify"):
                add_static_finding(
                    findings,
                    path=path,
                    repo_root=repo_root,
                    line_number=line_number,
                    rule_id="python-tls-verification-disabled",
                    message="requests verify=False disables TLS certificate verification.",
                )
    return {
        "scanner": "builtin-python-ast-static-security-rules",
        "scanned_files": scanned,
        "rules": [
            "python-dynamic-code-execution",
            "python-insecure-tempfile",
            "python-shell-command-api",
            "python-subprocess-shell-true",
            "python-syntax-error",
            "python-tls-verification-disabled",
            "python-unsafe-deserialization",
            "python-unsafe-yaml-load",
        ],
        "findings": findings,
        "status": "pass" if not findings else "fail",
    }


def scan_key_custody(repo_root: Path) -> dict[str, Any]:
    checks: list[dict[str, Any]] = []
    failures: list[dict[str, Any]] = []
    for expectation in KEY_CUSTODY_EXPECTATIONS:
        rel_path = str(expectation["path"])
        path = repo_root / rel_path
        exists = path.is_file()
        text = read_text(path) if exists else ""
        missing = [marker for marker in expectation["markers"] if marker not in text]
        check = {
            "name": expectation["name"],
            "path": rel_path,
            "status": "pass" if exists and not missing else "fail",
            "missing_markers": missing,
        }
        checks.append(check)
        if check["status"] != "pass":
            failures.append(check)
    return {
        "scanner": "builtin-key-custody-source-evidence",
        "checks": checks,
        "failures": failures,
        "external_evidence_required": KEY_CUSTODY_EXTERNAL_EVIDENCE,
        "status": "pass" if not failures else "fail",
    }


def parse_apt_install_packages(command: str) -> list[str]:
    matches = re.finditer(r"\bapt-get\s+install\b|\bapt\s+install\b", command)
    packages: list[str] = []
    for match in matches:
        rest = command[match.end() :]
        rest = re.split(r"\s+(?:&&|\|\||;)\s+", rest, maxsplit=1)[0]
        try:
            tokens = shlex.split(rest)
        except ValueError:
            tokens = rest.split()
        for token in tokens:
            if token.startswith("-"):
                continue
            if token in {"\\", "&&", ";"}:
                continue
            if "=" in token and token.split("=", 1)[0].isupper():
                continue
            packages.append(token)
    return packages


def parse_debian_depends(value: str) -> list[str]:
    packages: list[str] = []
    for chunk in value.split(","):
        package = chunk.strip()
        package = re.split(r"\s*[|(]", package, maxsplit=1)[0].strip()
        if package:
            packages.append(package)
    return packages


def add_dependency(
    dependencies: list[dict[str, str]],
    seen: set[tuple[str, str, str, str]],
    *,
    ecosystem: str,
    kind: str,
    name: str,
    source: str,
    package_manager: str,
    scope: str,
) -> None:
    key = (ecosystem, kind, name, source)
    if key in seen:
        return
    seen.add(key)
    dependencies.append(
        {
            "ecosystem": ecosystem,
            "kind": kind,
            "name": name,
            "source": source,
            "package_manager": package_manager,
            "scope": scope,
            "version": "NOASSERTION",
        }
    )


def xml_child_text(element: ET.Element, local_name: str) -> str:
    for child in list(element):
        if child.tag.rsplit("}", 1)[-1] == local_name:
            return (child.text or "").strip()
    return ""


def collect_maven_dependencies(path: Path, repo_root: Path) -> list[dict[str, str]]:
    dependencies: list[dict[str, str]] = []
    rel = repo_relative(path, repo_root)
    try:
        root = ET.fromstring(read_text(path))  # nosec B314
    except ET.ParseError:
        return dependencies

    def add_maven_item(kind: str, node: ET.Element, scope: str) -> None:
        group_id = xml_child_text(node, "groupId")
        artifact_id = xml_child_text(node, "artifactId")
        version = xml_child_text(node, "version") or "NOASSERTION"
        if not artifact_id:
            return
        name = f"{group_id}:{artifact_id}" if group_id else artifact_id
        dependencies.append(
            {
                "ecosystem": "maven",
                "kind": kind,
                "name": name,
                "source": rel,
                "package_manager": "maven",
                "scope": scope,
                "version": version,
            }
        )

    for element in root.iter():
        local_name = element.tag.rsplit("}", 1)[-1]
        if local_name == "dependency":
            scope = xml_child_text(element, "scope") or "compile"
            add_maven_item("maven-dependency", element, scope)
        elif local_name == "plugin":
            add_maven_item("maven-plugin", element, "build")
    return dependencies


def collect_dependencies(files: list[Path], repo_root: Path) -> dict[str, Any]:
    dependencies: list[dict[str, str]] = []
    seen: set[tuple[str, str, str, str]] = set()
    dependency_manifests: set[str] = set()

    for path in dockerfiles(files):
        rel = repo_relative(path, repo_root)
        for line in logical_lines(path):
            from_match = re.match(r"FROM\s+([^\s]+)", line, flags=re.IGNORECASE)
            if from_match:
                add_dependency(
                    dependencies,
                    seen,
                    ecosystem="oci",
                    kind="container-base-image",
                    name=from_match.group(1),
                    source=rel,
                    package_manager="dockerfile",
                    scope="container",
                )
            for package in parse_apt_install_packages(line):
                add_dependency(
                    dependencies,
                    seen,
                    ecosystem="debian",
                    kind="os-package",
                    name=package,
                    source=rel,
                    package_manager="apt",
                    scope="container",
                )

    deb_script = repo_root / "packaging/build-deb.sh"
    if deb_script.is_file():
        for match in re.finditer(r"^(Depends|Suggests|Recommends):\s*(.+)$", read_text(deb_script), flags=re.MULTILINE):
            field = match.group(1).lower()
            for package in parse_debian_depends(match.group(2)):
                add_dependency(
                    dependencies,
                    seen,
                    ecosystem="debian",
                    kind=f"package-{field}",
                    name=package,
                    source="packaging/build-deb.sh",
                    package_manager="dpkg",
                    scope="runtime",
                )

    rpm_script = repo_root / "packaging/build-rpm.sh"
    if rpm_script.is_file():
        for match in re.finditer(r"^(Requires|Recommends|Suggests)(?:\([^)]*\))?:\s*(.+)$", read_text(rpm_script), flags=re.MULTILINE):
            field = match.group(1).lower()
            package = match.group(2).strip()
            if package:
                add_dependency(
                    dependencies,
                    seen,
                    ecosystem="rpm",
                    kind=f"package-{field}",
                    name=package,
                    source="packaging/build-rpm.sh",
                    package_manager="rpm",
                    scope="runtime",
                )

    flake = repo_root / "flake.nix"
    if flake.is_file():
        for package in sorted(set(re.findall(r"\bpkgs\.([A-Za-z0-9_+-]+)", read_text(flake)))):
            if package in {"lib", "stdenv", "stdenvNoCC"}:
                continue
            add_dependency(
                dependencies,
                seen,
                ecosystem="nix",
                kind="nix-package-reference",
                name=package,
                source="flake.nix",
                package_manager="nix",
                    scope="build-or-runtime",
                )

    for path in files:
        if path.name == "pom.xml":
            dependency_manifests.add(repo_relative(path, repo_root))
            for dependency in collect_maven_dependencies(path, repo_root):
                key = (
                    dependency["ecosystem"],
                    dependency["kind"],
                    dependency["name"],
                    dependency["source"],
                )
                if key in seen:
                    continue
                seen.add(key)
                dependencies.append(dependency)

    dependencies.sort(key=lambda item: (item["ecosystem"], item["kind"], item["name"], item["source"]))
    notes = [
        "Versions are NOASSERTION when package manager resolution happens on build or install runners.",
    ]
    if dependency_manifests:
        notes.insert(0, "Dependency manifests found: " + ", ".join(sorted(dependency_manifests)))
    else:
        notes.insert(0, "No Python, Node, Go, Rust, Ruby, Java, or PHP dependency manifest was found in the tracked source tree.")
    return {
        "scanner": "builtin-source-dependency-inventory",
        "status": "pass",
        "summary": {
            "dependency_count": len(dependencies),
            "ecosystems": sorted({item["ecosystem"] for item in dependencies}),
            "sources": sorted({item["source"] for item in dependencies}),
        },
        "dependencies": dependencies,
        "notes": notes,
    }


def spdx_id(value: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9.-]+", "-", value).strip("-")
    if not cleaned:
        cleaned = hashlib.sha256(value.encode("utf-8")).hexdigest()[:12]
    if not cleaned[0].isalpha():
        cleaned = f"Package-{cleaned}"
    return f"SPDXRef-{cleaned[:80]}"


def generate_spdx_sbom(
    *, version: str, source_commit: str, generated_at: str, dependency_inventory: dict[str, Any]
) -> dict[str, Any]:
    root_spdx_id = "SPDXRef-Package-SSHFling"
    namespace_seed = f"sshfling:{version}:{source_commit}:{generated_at}"
    namespace_uuid = uuid.uuid5(uuid.NAMESPACE_URL, namespace_seed)
    packages: list[dict[str, Any]] = [
        {
            "SPDXID": root_spdx_id,
            "name": "SSHFling",
            "versionInfo": version,
            "downloadLocation": "NOASSERTION",
            "filesAnalyzed": False,
            "licenseConcluded": "LicenseRef-SSHFling-Commercial",
            "licenseDeclared": "LicenseRef-SSHFling-Commercial",
            "copyrightText": "Copyright (c) 2026 GRWLX. All rights reserved.",
        }
    ]
    relationships: list[dict[str, str]] = [
        {
            "spdxElementId": "SPDXRef-DOCUMENT",
            "relationshipType": "DESCRIBES",
            "relatedSpdxElement": root_spdx_id,
        }
    ]
    used_ids = {root_spdx_id}
    for item in dependency_inventory["dependencies"]:
        package_id = spdx_id(f"{item['ecosystem']}-{item['package_manager']}-{item['name']}")
        if package_id in used_ids:
            package_id = spdx_id(f"{item['ecosystem']}-{item['package_manager']}-{item['name']}-{item['source']}")
        used_ids.add(package_id)
        packages.append(
            {
                "SPDXID": package_id,
                "name": item["name"],
                "versionInfo": item["version"],
                "downloadLocation": "NOASSERTION",
                "filesAnalyzed": False,
                "licenseConcluded": "NOASSERTION",
                "licenseDeclared": "NOASSERTION",
                "supplier": "NOASSERTION",
                "externalRefs": [
                    {
                        "referenceCategory": "PACKAGE-MANAGER",
                        "referenceType": "purl",
                        "referenceLocator": f"pkg:generic/{item['name']}",
                    }
                ],
                "comment": f"{item['kind']} from {item['source']} ({item['package_manager']}, {item['scope']}).",
            }
        )
        relationships.append(
            {
                "spdxElementId": root_spdx_id,
                "relationshipType": "DEPENDS_ON",
                "relatedSpdxElement": package_id,
            }
        )

    return {
        "spdxVersion": "SPDX-2.3",
        "dataLicense": "CC0-1.0",
        "SPDXID": "SPDXRef-DOCUMENT",
        "name": f"SSHFling {version} release SBOM",
        "documentNamespace": f"https://sshfling.local/spdx/{namespace_uuid}",
        "creationInfo": {
            "created": generated_at,
            "creators": ["Tool: tools/release_security_scan.py"],
        },
        "packages": packages,
        "relationships": relationships,
        "hasExtractedLicensingInfos": [
            {
                "licenseId": "LicenseRef-SSHFling-Commercial",
                "extractedText": "SSHFling Commercial License; see LICENSE in the source release.",
                "name": "SSHFling Commercial License",
            }
        ],
    }


def scan_systemd_hardening(files: list[Path], repo_root: Path) -> dict[str, Any]:
    unit_results: list[dict[str, Any]] = []
    failures: list[dict[str, Any]] = []
    for path in systemd_units(files):
        text = read_text(path)
        keys = {
            match.group(1).strip()
            for match in re.finditer(r"^([A-Za-z][A-Za-z0-9]+)\s*=", text, flags=re.MULTILINE)
        }
        missing = sorted(key for key in SYSTEMD_HARDENING_KEYS if key not in keys)
        result = {
            "path": repo_relative(path, repo_root),
            "status": "pass" if not missing else "fail",
            "missing_hardening_keys": missing,
        }
        unit_results.append(result)
        if missing:
            failures.append(result)
    return {
        "scanner": "builtin-systemd-hardening-key-check",
        "expected_keys": SYSTEMD_HARDENING_KEYS,
        "units": unit_results,
        "failures": failures,
        "status": "pass" if not failures else "fail",
    }


def scan_dockerfile_hygiene(files: list[Path], repo_root: Path) -> dict[str, Any]:
    results: list[dict[str, Any]] = []
    failures: list[dict[str, Any]] = []
    for path in dockerfiles(files):
        rel = repo_relative(path, repo_root)
        text = read_text(path)
        issues: list[str] = []
        if "apt-get install" in text and "--no-install-recommends" not in text:
            issues.append("apt-get install without --no-install-recommends")
        if "apt-get install" in text and "rm -rf /var/lib/apt/lists/*" not in text:
            issues.append("apt package lists are not removed")
        if re.search(r"FROM\s+[^:\s]+(?:\s|$)", text, flags=re.IGNORECASE):
            issues.append("base image tag is not explicit")
        result = {
            "path": rel,
            "status": "pass" if not issues else "fail",
            "issues": issues,
        }
        results.append(result)
        if issues:
            failures.append(result)
    return {
        "scanner": "builtin-dockerfile-release-hygiene",
        "dockerfiles": results,
        "failures": failures,
        "status": "pass" if not failures else "fail",
    }


def run_command(
    *,
    name: str,
    command: list[str],
    cwd: Path,
    output_path: Path,
    timeout_seconds: int,
) -> dict[str, Any]:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    started_at = utc_now()
    try:
        completed = subprocess.run(
            command,
            cwd=cwd,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=timeout_seconds,
            check=False,
        )
        output = completed.stdout or ""
        output_path.write_text(output, encoding="utf-8", errors="replace")
        status = "pass" if completed.returncode == 0 else "fail"
        return {
            "name": name,
            "status": status,
            "command": command,
            "exit_code": completed.returncode,
            "started_at_utc": started_at,
            "finished_at_utc": utc_now(),
            "output_path": str(output_path),
            "output_bytes": output_path.stat().st_size,
        }
    except subprocess.TimeoutExpired as exc:
        output = (exc.stdout or "") if isinstance(exc.stdout, str) else ""
        output += f"\nCommand timed out after {timeout_seconds} seconds.\n"
        output_path.write_text(output, encoding="utf-8", errors="replace")
        return {
            "name": name,
            "status": "fail",
            "command": command,
            "exit_code": "timeout",
            "started_at_utc": started_at,
            "finished_at_utc": utc_now(),
            "output_path": str(output_path),
            "output_bytes": output_path.stat().st_size,
        }


def normalize_osv_result(result: dict[str, Any], output_path: Path) -> dict[str, Any]:
    if result.get("status") != "fail" or result.get("exit_code") != 128:
        return result
    output = output_path.read_text(encoding="utf-8", errors="replace") if output_path.exists() else ""
    if "No package sources found" not in output:
        return result
    result["status"] = "pass"
    result["reason"] = "OSV scanner found no package sources to evaluate"
    return result


def trivy_blocking_findings(trivy_json: Path) -> dict[str, Any]:
    payload = json.loads(trivy_json.read_text(encoding="utf-8"))
    blockers: list[dict[str, Any]] = []
    allowlisted: list[dict[str, Any]] = []
    for scan_result in payload.get("Results", []):
        target = str(scan_result.get("Target", ""))
        for kind in ("Vulnerabilities", "Secrets", "Misconfigurations"):
            for finding in scan_result.get(kind, []) or []:
                severity = str(finding.get("Severity", "")).upper()
                if severity not in {"HIGH", "CRITICAL"}:
                    continue
                finding_id = str(finding.get("VulnerabilityID") or finding.get("RuleID") or finding.get("ID") or "")
                summary = str(finding.get("Title") or finding.get("Message") or finding.get("PkgName") or "")
                row = {
                    "target": target,
                    "kind": kind,
                    "id": finding_id,
                    "severity": severity,
                    "summary": summary,
                }
                exception = TRIVY_MISCONFIG_ALLOWLIST.get((target, finding_id))
                if kind == "Misconfigurations" and exception:
                    row["exception"] = exception
                    allowlisted.append(row)
                else:
                    blockers.append(row)
    return {
        "blocking_findings": blockers,
        "allowlisted_findings": allowlisted,
    }


def optional_tool_results(
    *,
    repo_root: Path,
    output_dir: Path,
    files: list[Path],
    run_optional_tools: bool,
    strict_optional_tools: bool,
    timeout_seconds: int,
) -> list[dict[str, Any]]:
    tool_dir = output_dir / "optional-tools"
    tools: list[dict[str, Any]] = []

    shell_paths = [repo_relative(path, repo_root) for path in shell_files(files, repo_root)]
    python_paths = [repo_relative(path, repo_root) for path in python_files(files)]
    docker_paths = [repo_relative(path, repo_root) for path in dockerfiles(files)]
    systemd_paths = [repo_relative(path, repo_root) for path in systemd_units(files)]
    scanner_skip_dirs, scanner_skip_files = optional_scanner_exclusions(repo_root)
    syft_excludes = [f"./{path}" for path in OPTIONAL_SCANNER_EXCLUDED_PATHS]

    if shell_paths:
        tools.append(
            {
                "name": "shellcheck",
                "purpose": "shell linting",
                "binary": "shellcheck",
                "command": ["shellcheck", *shell_paths],
                "output": tool_dir / "shellcheck.log",
            }
        )
    if python_paths:
        tools.append(
            {
                "name": "bandit",
                "purpose": "Python SAST",
                "binary": "bandit",
                "command": [
                    "bandit",
                    "-q",
                    "--severity-level",
                    "medium",
                    "--confidence-level",
                    "medium",
                    "-f",
                    "json",
                    "-o",
                    str(tool_dir / "bandit.json"),
                    *python_paths,
                ],
                "output": tool_dir / "bandit.log",
            }
        )
    if docker_paths:
        tools.append(
            {
                "name": "hadolint",
                "purpose": "Dockerfile linting",
                "binary": "hadolint",
                "command": ["hadolint", "--failure-threshold", "error", *docker_paths],
                "output": tool_dir / "hadolint.log",
            }
        )
    if systemd_paths:
        tools.append(
            {
                "name": "systemd-analyze-security",
                "purpose": "systemd unit security review",
                "binary": "systemd-analyze",
                "command": [
                    "systemd-analyze",
                    "security",
                    "--offline=yes",
                    "--no-pager",
                    *systemd_paths,
                ],
                "output": tool_dir / "systemd-analyze-security.log",
            }
        )
    gitleaks_command = [
        "gitleaks",
        "detect",
        "--source",
        ".",
        "--redact",
        "--report-format",
        "json",
        "--report-path",
        str(tool_dir / "gitleaks.json"),
    ]
    if (repo_root / ".gitleaksignore").exists():
        gitleaks_command.extend(["--gitleaks-ignore-path", ".gitleaksignore"])

    tools.extend(
        [
            {
                "name": "syft",
                "purpose": "external SBOM generation",
                "binary": "syft",
                "command": [
                    "syft",
                    "dir:.",
                    "-o",
                    f"spdx-json={tool_dir / 'syft.spdx.json'}",
                    *[part for path in syft_excludes for part in ("--exclude", path)],
                ],
                "output": tool_dir / "syft.log",
            },
            {
                "name": "gitleaks",
                "purpose": "external secret scanning",
                "binary": "gitleaks",
                "command": gitleaks_command,
                "output": tool_dir / "gitleaks.log",
            },
            {
                "name": "trivy-fs",
                "purpose": "filesystem vulnerability, secret, and misconfiguration scan",
                "binary": "trivy",
                "command": [
                    "trivy",
                    "fs",
                    "--scanners",
                    "vuln,secret,misconfig",
                    "--severity",
                    "HIGH,CRITICAL",
                    "--exit-code",
                    "0",
                    "--format",
                    "json",
                    "--output",
                    str(tool_dir / "trivy-fs.json"),
                    *[part for path in scanner_skip_dirs for part in ("--skip-dirs", path)],
                    *[part for path in scanner_skip_files for part in ("--skip-files", path)],
                    ".",
                ],
                "output": tool_dir / "trivy-fs.log",
            },
            {
                "name": "osv-scanner",
                "purpose": "software composition analysis against OSV vulnerability data",
                "binary": "osv-scanner",
                "command": [
                    "osv-scanner",
                    "scan",
                    "--format",
                    "json",
                    "--output",
                    str(tool_dir / "osv-scanner.json"),
                    "--skip-git",
                    "--recursive",
                    ".",
                ],
                "output": tool_dir / "osv-scanner.log",
            },
        ]
    )

    results: list[dict[str, Any]] = []
    for tool in tools:
        binary = str(tool["binary"])
        missing_status = "blocked" if strict_optional_tools else "skipped"
        if not run_optional_tools:
            results.append(
                {
                    "name": tool["name"],
                    "purpose": tool["purpose"],
                    "status": missing_status if strict_optional_tools else "skipped",
                    "reason": "optional tools were not requested",
                    "command": tool["command"],
                    "output_path": "",
                    "exit_code": "not_run",
                }
            )
            continue
        if shutil.which(binary) is None:
            results.append(
                {
                    "name": tool["name"],
                    "purpose": tool["purpose"],
                    "status": missing_status,
                    "reason": f"{binary} is not installed",
                    "command": tool["command"],
                    "output_path": "",
                    "exit_code": "missing",
                }
            )
            continue
        result = run_command(
            name=str(tool["name"]),
            command=[str(part) for part in tool["command"]],
            cwd=repo_root,
            output_path=Path(tool["output"]),
            timeout_seconds=timeout_seconds,
        )
        result["purpose"] = tool["purpose"]
        if tool["name"] == "bandit":
            bandit_json = tool_dir / "bandit.json"
            if bandit_json.exists():
                result["artifact_path"] = str(bandit_json)
        elif tool["name"] == "syft":
            syft_json = tool_dir / "syft.spdx.json"
            if syft_json.exists():
                result["artifact_path"] = str(syft_json)
        elif tool["name"] == "gitleaks":
            gitleaks_json = tool_dir / "gitleaks.json"
            if gitleaks_json.exists():
                result["artifact_path"] = str(gitleaks_json)
        elif tool["name"] == "trivy-fs":
            trivy_json = tool_dir / "trivy-fs.json"
            if trivy_json.exists():
                result["artifact_path"] = str(trivy_json)
                trivy_policy = trivy_blocking_findings(trivy_json)
                result["trivy_blocking_findings"] = trivy_policy["blocking_findings"]
                result["trivy_allowlisted_findings"] = trivy_policy["allowlisted_findings"]
                if trivy_policy["blocking_findings"]:
                    result["status"] = "fail"
                    result["reason"] = f"{len(trivy_policy['blocking_findings'])} high/critical Trivy findings are not allowlisted"
                elif result["status"] == "pass":
                    result["reason"] = (
                        f"0 blocking high/critical findings; "
                        f"{len(trivy_policy['allowlisted_findings'])} documented root-container exceptions"
                    )
        elif tool["name"] == "osv-scanner":
            result = normalize_osv_result(result, tool_dir / "osv-scanner.log")
            osv_json = tool_dir / "osv-scanner.json"
            if osv_json.exists():
                result["artifact_path"] = str(osv_json)
        results.append(result)
    return results


def markdown_report(payload: dict[str, Any]) -> str:
    lines = [
        "# Release Security Scan Evidence",
        "",
        f"- Generated at UTC: {payload['generated_at_utc']}",
        f"- Release version: {payload['release_version']}",
        f"- Source commit: {payload['source_commit']}",
        f"- Source tree dirty: {payload.get('source_tree_dirty', False)}",
        f"- Dirty fingerprint SHA-256: {payload.get('dirty_fingerprint_sha256', 'NOT_APPLICABLE')}",
        f"- Overall status: {payload['overall_status'].upper()}",
        "",
        "## Baseline Checks",
        "",
        "| Check | Status | Summary |",
        "| --- | --- | --- |",
    ]
    baseline = payload["baseline_checks"]
    lines.append(
        f"| Secret scan | {baseline['secret_scan']['status']} | "
        f"{len(baseline['secret_scan']['findings'])} findings across {baseline['secret_scan']['scanned_files']} files |"
    )
    lines.append(
        f"| License scan | {baseline['license_scan']['status']} | "
        f"{len(baseline['license_scan']['failures'])} failed license marker checks |"
    )
    lines.append(
        f"| Shell static security | {baseline['shell_static']['status']} | "
        f"{len(baseline['shell_static']['findings'])} findings across {baseline['shell_static']['scanned_files']} files |"
    )
    lines.append(
        f"| Python static security | {baseline['python_static']['status']} | "
        f"{len(baseline['python_static']['findings'])} findings across {baseline['python_static']['scanned_files']} files |"
    )
    lines.append(
        f"| Dependency inventory | {baseline['dependency_inventory']['status']} | "
        f"{baseline['dependency_inventory']['summary']['dependency_count']} dependency entries |"
    )
    lines.append(
        f"| Dockerfile hygiene | {baseline['dockerfile_hygiene']['status']} | "
        f"{len(baseline['dockerfile_hygiene']['failures'])} Dockerfile findings |"
    )
    lines.append(
        f"| systemd hardening | {baseline['systemd_hardening']['status']} | "
        f"{len(baseline['systemd_hardening']['failures'])} unit hardening findings |"
    )
    lines.append(
        f"| Key custody source evidence | {baseline['key_custody']['status']} | "
        f"{len(baseline['key_custody']['failures'])} failed source custody checks; "
        f"{len(baseline['key_custody']['external_evidence_required'])} external evidence items still required |"
    )
    lines.extend(["", "## Optional Tools", "", "| Tool | Status | Reason or exit |", "| --- | --- | --- |"])
    for result in payload["optional_tools"]:
        reason = result.get("reason") or f"exit={result.get('exit_code')}"
        lines.append(f"| {result['name']} | {result['status']} | {reason} |")
    lines.append("")
    return "\n".join(lines)


def status_to_result(status: str) -> str:
    lowered = status.lower()
    if lowered == "pass":
        return "pass"
    if lowered == "fail":
        return "fail"
    if lowered == "blocked":
        return "blocked"
    return "skipped"


def make_row(
    *,
    index: int,
    status: str,
    version: str,
    source_commit: str,
    generated_at: str,
    control_area: str,
    check_name: str,
    expected_result: str,
    actual_result: str,
    evidence_ref: str,
    evidence_sha256: str,
    evidence_source: str,
    blocker_reason: str = "NONE",
    notes: str = "",
) -> dict[str, str]:
    readiness_status = status.upper()
    if readiness_status == "SKIPPED":
        blocker = "NONE"
    elif readiness_status == "BLOCKED":
        blocker = blocker_reason or "Required optional release scanner did not run."
    else:
        blocker = blocker_reason if readiness_status == "FAIL" else "NONE"
    return {
        "row_id": f"SEC-{index:05d}",
        "readiness_status": readiness_status,
        "result": status_to_result(status),
        "release_version": version,
        "source_commit": source_commit,
        "support_tier": "REQUIRED" if readiness_status in {"PASS", "FAIL"} else "OPTIONAL",
        "workflow_phase": "security_scan",
        "control_area": control_area,
        "check_name": check_name,
        "expected_result": expected_result,
        "actual_result": actual_result,
        "required_evidence": (
            "Generated release security report, static scan reports, SBOM, dependency inventory, "
            "license report, key custody report, matrix, and manifest."
        ),
        "evidence_source": evidence_source,
        "evidence_ref": evidence_ref,
        "evidence_sha256": evidence_sha256,
        "workflow_name": os.environ.get("GITHUB_WORKFLOW") or "Release security scan",
        "workflow_run_url": workflow_run_url(),
        "workflow_job": os.environ.get("GITHUB_JOB") or "release-security-scan",
        "signer_or_key_fingerprint": "NOT_APPLICABLE",
        "exception_id": "NONE",
        "exception_owner": "NONE",
        "exception_expires": "NONE",
        "blocker_reason": blocker,
        "reviewer": "release-security-scan-generator",
        "reviewed_at_utc": generated_at,
        "notes": notes,
    }


def write_matrix(path: Path, rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=MATRIX_FIELDS)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def generate(args: argparse.Namespace) -> int:
    repo_root = Path(args.repo_root).resolve()
    output_dir = (repo_root / args.output_dir).resolve()
    repo_relative(output_dir, repo_root)

    source_commit = args.source_commit or os.environ.get("GITHUB_SHA") or current_commit(repo_root)
    if not source_commit:
        raise SystemExit("source commit is required; pass --source-commit outside a git checkout")
    worktree_status = git_worktree_status(repo_root)
    source_tree_dirty = bool(worktree_status.strip())
    if source_tree_dirty and not args.allow_dirty:
        raise SystemExit("release security evidence requires a clean git working tree; commit changes or pass --allow-dirty for non-release evidence")
    dirty_fingerprint = git_dirty_fingerprint(repo_root, worktree_status) if source_tree_dirty else ""

    output_dir.mkdir(parents=True, exist_ok=True)

    run_optional_tools = args.run_optional_tools or is_truthy(os.environ.get("RELEASE_SECURITY_RUN_OPTIONAL_TOOLS"))
    strict_optional_tools = args.strict_optional_tools or is_truthy(
        os.environ.get("RELEASE_SECURITY_STRICT_OPTIONAL_TOOLS")
    )

    generated_at = utc_now()
    files = tracked_files(repo_root)

    secret_report = scan_secrets(files, repo_root)
    license_report = scan_license(repo_root)
    shell_static_report = scan_shell_static(files, repo_root)
    python_static_report = scan_python_static(files, repo_root)
    dependency_inventory = collect_dependencies(files, repo_root)
    sbom = generate_spdx_sbom(
        version=args.version,
        source_commit=source_commit,
        generated_at=generated_at,
        dependency_inventory=dependency_inventory,
    )
    systemd_report = scan_systemd_hardening(files, repo_root)
    dockerfile_report = scan_dockerfile_hygiene(files, repo_root)
    key_custody_report = scan_key_custody(repo_root)
    optional_results = optional_tool_results(
        repo_root=repo_root,
        output_dir=output_dir,
        files=files,
        run_optional_tools=run_optional_tools,
        strict_optional_tools=strict_optional_tools,
        timeout_seconds=args.optional_timeout_seconds,
    )

    baseline_checks = {
        "secret_scan": secret_report,
        "license_scan": license_report,
        "shell_static": shell_static_report,
        "python_static": python_static_report,
        "dependency_inventory": dependency_inventory,
        "dockerfile_hygiene": dockerfile_report,
        "systemd_hardening": systemd_report,
        "key_custody": key_custody_report,
    }
    baseline_failed = any(check["status"] != "pass" for check in baseline_checks.values())
    optional_failed = any(result["status"] in {"fail", "blocked"} for result in optional_results)
    overall_status = "fail" if baseline_failed or optional_failed else "pass"

    secret_path = output_dir / "secret-scan-report.json"
    license_path = output_dir / "license-report.json"
    shell_static_path = output_dir / "shell-static-security-report.json"
    python_static_path = output_dir / "python-static-security-report.json"
    dependency_path = output_dir / "dependency-inventory.json"
    sbom_path = output_dir / "sbom.spdx.json"
    dockerfile_path = output_dir / "dockerfile-hygiene-report.json"
    systemd_path = output_dir / "systemd-hardening-report.json"
    key_custody_path = output_dir / "key-custody-report.json"
    report_path = output_dir / "security-scan-report.json"
    report_md_path = output_dir / "security-scan-report.md"
    matrix_path = output_dir / "security-scan-matrix.csv"
    manifest_path = output_dir / "security-scan-manifest.json"

    write_json(secret_path, secret_report)
    write_json(license_path, license_report)
    write_json(shell_static_path, shell_static_report)
    write_json(python_static_path, python_static_report)
    write_json(dependency_path, dependency_inventory)
    write_json(sbom_path, sbom)
    write_json(dockerfile_path, dockerfile_report)
    write_json(systemd_path, systemd_report)
    write_json(key_custody_path, key_custody_report)

    report_payload: dict[str, Any] = {
        "schema_version": 1,
        "release_version": args.version,
        "source_commit": source_commit,
        "source_tree_dirty": source_tree_dirty,
        "dirty_fingerprint_sha256": dirty_fingerprint or "NOT_APPLICABLE",
        "generated_at_utc": generated_at,
        "overall_status": overall_status,
        "run_optional_tools": run_optional_tools,
        "strict_optional_tools": strict_optional_tools,
        "tracked_files": len(files),
        "baseline_checks": baseline_checks,
        "optional_tools": optional_results,
        "evidence_files": {
            "secret_scan": repo_relative(secret_path, repo_root),
            "license_scan": repo_relative(license_path, repo_root),
            "shell_static": repo_relative(shell_static_path, repo_root),
            "python_static": repo_relative(python_static_path, repo_root),
            "dependency_inventory": repo_relative(dependency_path, repo_root),
            "sbom": repo_relative(sbom_path, repo_root),
            "dockerfile_hygiene": repo_relative(dockerfile_path, repo_root),
            "systemd_hardening": repo_relative(systemd_path, repo_root),
            "key_custody": repo_relative(key_custody_path, repo_root),
            "report_markdown": repo_relative(report_md_path, repo_root),
            "matrix": repo_relative(matrix_path, repo_root),
            "manifest": repo_relative(manifest_path, repo_root),
        },
    }
    write_json(report_path, report_payload)
    write_text(report_md_path, markdown_report(report_payload))

    evidence_hashes = {
        "secret_scan": file_sha256(secret_path),
        "license_scan": file_sha256(license_path),
        "shell_static": file_sha256(shell_static_path),
        "python_static": file_sha256(python_static_path),
        "dependency_inventory": file_sha256(dependency_path),
        "sbom": file_sha256(sbom_path),
        "dockerfile_hygiene": file_sha256(dockerfile_path),
        "systemd_hardening": file_sha256(systemd_path),
        "key_custody": file_sha256(key_custody_path),
        "report": file_sha256(report_path),
        "report_markdown": file_sha256(report_md_path),
    }

    rows: list[dict[str, str]] = []
    rows.append(
        make_row(
            index=len(rows) + 1,
            status=secret_report["status"],
            version=args.version,
            source_commit=source_commit,
            generated_at=generated_at,
            control_area="secret_scanning",
            check_name="builtin-secret-scan",
            expected_result="No high-confidence committed secret patterns are present in tracked source.",
            actual_result=f"{len(secret_report['findings'])} findings across {secret_report['scanned_files']} scanned files.",
            evidence_ref=repo_relative(secret_path, repo_root),
            evidence_sha256=evidence_hashes["secret_scan"],
            evidence_source="builtin-secret-pattern-scan",
            blocker_reason="High-confidence secret finding requires review before release."
            if secret_report["status"] != "pass"
            else "NONE",
        )
    )
    rows.append(
        make_row(
            index=len(rows) + 1,
            status=license_report["status"],
            version=args.version,
            source_commit=source_commit,
            generated_at=generated_at,
            control_area="license_compliance",
            check_name="builtin-license-marker-scan",
            expected_result="Commercial license markers are present in source and package metadata generators.",
            actual_result=f"{len(license_report['failures'])} failed license marker checks.",
            evidence_ref=repo_relative(license_path, repo_root),
            evidence_sha256=evidence_hashes["license_scan"],
            evidence_source="builtin-license-marker-scan",
            blocker_reason="License metadata mismatch requires release owner review."
            if license_report["status"] != "pass"
            else "NONE",
        )
    )
    rows.append(
        make_row(
            index=len(rows) + 1,
            status=shell_static_report["status"],
            version=args.version,
            source_commit=source_commit,
            generated_at=generated_at,
            control_area="source_static_analysis",
            check_name="builtin-shell-static-security",
            expected_result="Shell release scripts avoid high-risk downloader, temp-file, logging, chmod, and command-line secret patterns.",
            actual_result=(
                f"{len(shell_static_report['findings'])} findings across "
                f"{shell_static_report['scanned_files']} shell files."
            ),
            evidence_ref=repo_relative(shell_static_path, repo_root),
            evidence_sha256=evidence_hashes["shell_static"],
            evidence_source="builtin-shell-static-security-rules",
            blocker_reason="Shell static security finding requires release owner review."
            if shell_static_report["status"] != "pass"
            else "NONE",
        )
    )
    rows.append(
        make_row(
            index=len(rows) + 1,
            status=python_static_report["status"],
            version=args.version,
            source_commit=source_commit,
            generated_at=generated_at,
            control_area="source_static_analysis",
            check_name="builtin-python-ast-static-security",
            expected_result="Python release and security tooling avoids dynamic execution, shell=True, unsafe deserialization, and TLS bypasses.",
            actual_result=(
                f"{len(python_static_report['findings'])} findings across "
                f"{python_static_report['scanned_files']} Python files."
            ),
            evidence_ref=repo_relative(python_static_path, repo_root),
            evidence_sha256=evidence_hashes["python_static"],
            evidence_source="builtin-python-ast-static-security-rules",
            blocker_reason="Python static security finding requires release owner review."
            if python_static_report["status"] != "pass"
            else "NONE",
        )
    )
    rows.append(
        make_row(
            index=len(rows) + 1,
            status=dependency_inventory["status"],
            version=args.version,
            source_commit=source_commit,
            generated_at=generated_at,
            control_area="dependency_inventory",
            check_name="builtin-dependency-inventory",
            expected_result="Runtime/build dependency inputs are inventoried from tracked source manifests.",
            actual_result=(
                f"{dependency_inventory['summary']['dependency_count']} dependency entries across "
                f"{', '.join(dependency_inventory['summary']['ecosystems']) or 'no ecosystems'}."
            ),
            evidence_ref=repo_relative(dependency_path, repo_root),
            evidence_sha256=evidence_hashes["dependency_inventory"],
            evidence_source="builtin-source-dependency-inventory",
        )
    )
    rows.append(
        make_row(
            index=len(rows) + 1,
            status="pass",
            version=args.version,
            source_commit=source_commit,
            generated_at=generated_at,
            control_area="sbom",
            check_name="builtin-spdx-sbom",
            expected_result="A source-derived SPDX 2.3 SBOM is generated for release evidence.",
            actual_result=f"SPDX SBOM generated with {len(sbom['packages'])} package entries.",
            evidence_ref=repo_relative(sbom_path, repo_root),
            evidence_sha256=evidence_hashes["sbom"],
            evidence_source="builtin-spdx-json-generator",
        )
    )
    rows.append(
        make_row(
            index=len(rows) + 1,
            status=dockerfile_report["status"],
            version=args.version,
            source_commit=source_commit,
            generated_at=generated_at,
            control_area="container_hygiene",
            check_name="builtin-dockerfile-hygiene",
            expected_result="Dockerfiles use explicit base tags, no-recommends apt installs, and remove apt package lists.",
            actual_result=f"{len(dockerfile_report['failures'])} Dockerfile hygiene findings.",
            evidence_ref=repo_relative(dockerfile_path, repo_root),
            evidence_sha256=evidence_hashes["dockerfile_hygiene"],
            evidence_source="builtin-dockerfile-hygiene",
            blocker_reason="Dockerfile hygiene finding requires release owner review."
            if dockerfile_report["status"] != "pass"
            else "NONE",
        )
    )
    rows.append(
        make_row(
            index=len(rows) + 1,
            status=systemd_report["status"],
            version=args.version,
            source_commit=source_commit,
            generated_at=generated_at,
            control_area="systemd_hardening",
            check_name="builtin-systemd-hardening-keys",
            expected_result="Tracked systemd units contain the expected hardening keys for release service units.",
            actual_result=f"{len(systemd_report['failures'])} systemd hardening findings.",
            evidence_ref=repo_relative(systemd_path, repo_root),
            evidence_sha256=evidence_hashes["systemd_hardening"],
            evidence_source="builtin-systemd-hardening-key-check",
            blocker_reason="systemd hardening marker gap requires release owner review."
            if systemd_report["status"] != "pass"
            else "NONE",
        )
    )
    rows.append(
        make_row(
            index=len(rows) + 1,
            status=key_custody_report["status"],
            version=args.version,
            source_commit=source_commit,
            generated_at=generated_at,
            control_area="key_custody",
            check_name="builtin-key-custody-source-evidence",
            expected_result="Source-controlled service, package, and publishing paths document restricted key custody markers.",
            actual_result=(
                f"{len(key_custody_report['failures'])} failed source checks; "
                f"{len(key_custody_report['external_evidence_required'])} external custody evidence items required."
            ),
            evidence_ref=repo_relative(key_custody_path, repo_root),
            evidence_sha256=evidence_hashes["key_custody"],
            evidence_source="builtin-key-custody-source-evidence",
            blocker_reason="Key custody source evidence gap requires release owner review."
            if key_custody_report["status"] != "pass"
            else "NONE",
            notes="The scanner verifies source markers only; production key custody proof must still be attached to the release packet.",
        )
    )

    for result in optional_results:
        artifact_value = str(result.get("artifact_path") or result.get("output_path") or "")
        artifact_path = Path(artifact_value) if artifact_value else None
        if artifact_path is not None and artifact_path.exists() and artifact_path.is_file():
            evidence_ref = repo_relative(artifact_path, repo_root)
            evidence_sha = file_sha256(artifact_path)
        else:
            evidence_ref = repo_relative(report_path, repo_root)
            evidence_sha = evidence_hashes["report"]
        status = str(result["status"])
        actual = result.get("reason") or f"{result['name']} exit_code={result.get('exit_code')}"
        rows.append(
            make_row(
                index=len(rows) + 1,
                status=status,
                version=args.version,
                source_commit=source_commit,
                generated_at=generated_at,
                control_area="optional_external_scanner",
                check_name=f"optional-{result['name']}",
                expected_result=f"{result['purpose']} passes when the optional scanner is selected.",
                actual_result=str(actual),
                evidence_ref=evidence_ref,
                evidence_sha256=evidence_sha,
                evidence_source="optional-external-scanner",
                blocker_reason=str(actual) if status == "blocked" else "NONE",
                notes="Missing optional scanners do not block the baseline release scan unless strict mode is enabled.",
            )
        )

    write_matrix(matrix_path, rows)

    manifest_entries: dict[str, dict[str, Any]] = {}
    for row in rows:
        evidence_ref = row["evidence_ref"]
        if evidence_ref not in manifest_entries:
            manifest_entries[evidence_ref] = {
                "evidence_id": evidence_ref,
                "evidence_ref": evidence_ref,
                "artifact_path": evidence_ref,
                "sha256": row["evidence_sha256"],
                "source_commit": source_commit,
                "result": row["result"],
                "release_version": args.version,
                "rows": [],
            }
        manifest_entries[evidence_ref]["rows"].append(row["row_id"])
        if manifest_entries[evidence_ref]["result"] != "pass" and row["result"] == "pass":
            manifest_entries[evidence_ref]["result"] = "pass"

    report_ref = repo_relative(report_path, repo_root)
    manifest_entries.setdefault(
        report_ref,
        {
            "evidence_id": report_ref,
            "evidence_ref": report_ref,
            "artifact_path": report_ref,
            "sha256": evidence_hashes["report"],
            "source_commit": source_commit,
            "result": overall_status,
            "release_version": args.version,
            "rows": [],
        },
    )
    report_md_ref = repo_relative(report_md_path, repo_root)
    manifest_entries.setdefault(
        report_md_ref,
        {
            "evidence_id": report_md_ref,
            "evidence_ref": report_md_ref,
            "artifact_path": report_md_ref,
            "sha256": evidence_hashes["report_markdown"],
            "source_commit": source_commit,
            "result": overall_status,
            "release_version": args.version,
            "rows": [],
        },
    )

    manifest_payload = {
        "schema_version": 1,
        "generated_at_utc": generated_at,
        "evidence": sorted(manifest_entries.values(), key=lambda item: item["evidence_id"]),
    }
    write_json(manifest_path, manifest_payload)

    print(f"wrote release security report: {report_path}")
    print(f"wrote release security markdown: {report_md_path}")
    print(f"wrote release security manifest: {manifest_path}")
    print(f"wrote release security matrix: {matrix_path}")
    print(f"release security rows: {len(rows)}")
    print(f"release security status: {overall_status}")
    return 1 if overall_status != "pass" else 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate release security, SBOM, license, and dependency evidence.")
    parser.add_argument("--version", required=True)
    parser.add_argument("--source-commit")
    parser.add_argument("--repo-root", default=".")
    parser.add_argument("--output-dir", default="docs/release/enterprise-release-evidence/security-scans")
    parser.add_argument("--allow-dirty", action="store_true", help="permit non-release evidence from a dirty working tree")
    parser.add_argument("--run-optional-tools", action="store_true")
    parser.add_argument("--strict-optional-tools", action="store_true")
    parser.add_argument("--optional-timeout-seconds", type=int, default=600)
    args = parser.parse_args()
    return generate(args)


if __name__ == "__main__":
    sys.exit(main())
