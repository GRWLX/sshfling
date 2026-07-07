#!/usr/bin/env python3
"""Validate generated enterprise release matrix evidence.

The release matrix under docs/release is intentionally generated and ignored.
This validator gives CI and release operators a tracked rule set for deciding
whether generated PASS rows are backed by immutable evidence.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import sys
from collections import Counter
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any


SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
PASS = "PASS"
FAIL = "FAIL"
BLOCKED = "BLOCKED"
SKIPPED = "SKIPPED"
DEFAULT_VALIDATION_MATRIX = "docs/release/enterprise-release-evidence/security-scans/security-scan-matrix.csv"
DEFAULT_VALIDATION_MANIFEST = "docs/release/enterprise-release-evidence/security-scans/security-scan-manifest.json"
DEFAULT_GENERATED_MANIFEST = "docs/release/evidence-manifest.json"
PLACEHOLDERS = {"", "NONE", "NOT_APPLICABLE", "N/A", "NA", "TBD", "TODO", "PENDING", "MISSING"}


def is_missing(value: Any) -> bool:
    return str(value or "").strip().upper() in PLACEHOLDERS


def manifest_entry_id(item: dict[str, Any]) -> str:
    return str(
        item.get("evidence_id")
        or item.get("evidence_ref")
        or item.get("ref")
        or item.get("artifact_path")
        or item.get("log_path")
        or ""
    ).strip()


def is_external_ref(value: str) -> bool:
    return value.startswith(("http://", "https://"))


def repo_relative(path: Path, repo_root: Path, label: str) -> str:
    resolved = path.resolve()
    try:
        return resolved.relative_to(repo_root.resolve()).as_posix()
    except ValueError as exc:
        raise SystemExit(f"{label} must stay inside repo: {path}") from exc


def path_uses_symlink_component(root: Path, rel_path: str) -> bool:
    if Path(rel_path).is_absolute():
        return False
    current = root
    for part in Path(rel_path).parts:
        if part in {"", "."}:
            continue
        current = current / part
        if current.is_symlink():
            return True
    return False


def load_manifest(path: Path) -> dict[str, dict[str, Any]]:
    if not path.exists():
        raise SystemExit(f"evidence manifest not found: {path}")
    data = json.loads(path.read_text(encoding="utf-8"))
    entries = data if isinstance(data, list) else data.get("evidence") or data.get("entries") or []
    if not isinstance(entries, list):
        raise SystemExit("evidence manifest must be a list or contain an 'evidence' or 'entries' list")

    by_id: dict[str, dict[str, Any]] = {}
    for index, item in enumerate(entries, 1):
        if not isinstance(item, dict):
            raise SystemExit(f"manifest entry {index} must be an object")
        evidence_id = manifest_entry_id(item)
        if not evidence_id:
            raise SystemExit(f"manifest entry {index} is missing evidence_id/evidence_ref")
        if evidence_id in by_id:
            raise SystemExit(f"duplicate evidence_id in manifest: {evidence_id}")
        by_id[evidence_id] = item
    return by_id


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def evidence_id(row: dict[str, str]) -> str:
    explicit = row.get("evidence_id", "").strip()
    if explicit:
        return explicit
    return row.get("evidence_ref", "").strip()


def manifest_covers_row(entry: dict[str, Any], row: dict[str, str]) -> bool:
    row_id = row.get("row_id", "").strip()
    return row_id in set(manifest_row_ids(entry))


def manifest_row_field(entry: dict[str, Any]) -> Any:
    if "rows" in entry:
        return entry.get("rows")
    if "row_ids" in entry:
        return entry.get("row_ids")
    return entry.get("row_id")


def manifest_row_ids(entry: dict[str, Any]) -> list[str]:
    rows = manifest_row_field(entry)
    if isinstance(rows, str):
        return [rows.strip()] if rows.strip() else []
    if isinstance(rows, list):
        return [str(item).strip() for item in rows if str(item).strip()]
    return []


def validate_manifest_row_coverage(manifest: dict[str, dict[str, Any]], matrix_row_ids: set[str]) -> list[str]:
    errors: list[str] = []
    covered_by: dict[str, str] = {}

    for eid, entry in manifest.items():
        rows = manifest_row_field(entry)
        if rows is None:
            continue
        if not isinstance(rows, (str, list)):
            errors.append(f"manifest entry {eid} rows must be a string or list")
            continue

        row_ids = manifest_row_ids(entry)
        seen_in_entry: set[str] = set()
        for row_id in row_ids:
            if row_id in seen_in_entry:
                errors.append(f"manifest entry {eid} duplicates row_id: {row_id}")
            seen_in_entry.add(row_id)
            if row_id not in matrix_row_ids:
                errors.append(f"manifest entry {eid} references unknown row_id: {row_id}")
            previous = covered_by.get(row_id)
            if previous and previous != eid:
                errors.append(f"manifest row_id {row_id} is covered by multiple entries: {previous}, {eid}")
            else:
                covered_by[row_id] = eid

    return errors


def validate_pass_row(
    row: dict[str, str],
    manifest: dict[str, dict[str, Any]],
    repo_root: Path,
    hash_cache: dict[Path, str],
) -> list[str]:
    errors: list[str] = []
    row_id = row.get("row_id", "").strip() or "<missing-row-id>"
    evidence_ref = row.get("evidence_ref", "").strip()
    evidence_hash = row.get("evidence_sha256", "").strip().lower()
    source_commit = row.get("source_commit", "").strip()
    eid = evidence_id(row)

    if "result" in row and str(row.get("result", "")).strip().lower() != "pass":
        errors.append(f"{row_id}: PASS row result is not 'pass'")
    if is_missing(source_commit):
        errors.append(f"{row_id}: PASS row is missing source_commit")
    if is_missing(evidence_ref):
        errors.append(f"{row_id}: PASS row is missing evidence_ref")
    if not SHA256_RE.fullmatch(evidence_hash):
        errors.append(f"{row_id}: PASS row evidence_sha256 is not a real sha256")
    if not eid or eid not in manifest:
        errors.append(f"{row_id}: PASS row evidence is missing from manifest: {eid or '<empty>'}")
        return errors

    entry = manifest[eid]
    manifest_ref = str(entry.get("evidence_ref") or entry.get("ref") or "").strip()
    if manifest_ref and evidence_ref and manifest_ref != evidence_ref:
        errors.append(f"{row_id}: manifest evidence_ref for {eid} does not match row")

    result = str(entry.get("result", "")).lower()
    if result != "pass":
        errors.append(f"{row_id}: manifest result for {eid} is {result!r}, expected 'pass'")
    if is_missing(entry.get("source_commit")):
        errors.append(f"{row_id}: manifest source_commit for {eid} is missing")
    elif source_commit and str(entry.get("source_commit", "")).strip() != source_commit:
        errors.append(f"{row_id}: manifest source_commit for {eid} does not match row")
    if not manifest_covers_row(entry, row):
        errors.append(f"{row_id}: manifest entry {eid} does not cover this row")

    manifest_hash = str(entry.get("sha256", "")).strip().lower()
    if not SHA256_RE.fullmatch(manifest_hash):
        errors.append(f"{row_id}: manifest sha256 for {eid} is not a real sha256")
    elif evidence_hash and manifest_hash and evidence_hash != manifest_hash:
        errors.append(f"{row_id}: row sha256 does not match manifest sha256 for {eid}")

    artifact_path = str(
        entry.get("artifact_path") or entry.get("log_path") or entry.get("evidence_ref") or evidence_ref or ""
    ).strip()
    if artifact_path and not is_external_ref(artifact_path):
        raw_local_path = repo_root / artifact_path
        local_path = raw_local_path.resolve()
        try:
            local_path.relative_to(repo_root.resolve())
        except ValueError:
            errors.append(f"{row_id}: manifest artifact path escapes repo: {artifact_path}")
        else:
            if path_uses_symlink_component(repo_root, artifact_path):
                errors.append(f"{row_id}: manifest artifact path uses symlink: {artifact_path}")
            elif not local_path.exists():
                errors.append(f"{row_id}: manifest artifact path does not exist: {artifact_path}")
            elif SHA256_RE.fullmatch(manifest_hash):
                if local_path not in hash_cache:
                    hash_cache[local_path] = file_sha256(local_path)
                actual = hash_cache[local_path]
                if actual != manifest_hash:
                    errors.append(f"{row_id}: manifest sha256 does not match artifact {artifact_path}")

    return errors


def status_for_row(row: dict[str, str]) -> str:
    return (row.get("readiness_status") or row.get("result") or row.get("status") or "").strip().upper()


def parse_exception_expiry(value: str) -> date | None:
    normalized = value.strip()
    if not normalized:
        return None
    if normalized.endswith("Z"):
        normalized = normalized[:-1] + "+00:00"
    try:
        return datetime.fromisoformat(normalized).date()
    except ValueError:
        pass
    try:
        return date.fromisoformat(normalized)
    except ValueError:
        return None


def validate_approved_exception(row: dict[str, str], row_id: str) -> list[str]:
    errors: list[str] = []
    exception_id = row.get("exception_id", "").strip()
    exception_owner = row.get("exception_owner", "").strip()
    exception_expires = row.get("exception_expires", "").strip()
    reason = (
        row.get("blocker_reason", "").strip()
        or row.get("actual_result", "").strip()
        or row.get("notes", "").strip()
    )

    if is_missing(exception_id):
        errors.append(f"{row_id}: approved exception is missing exception_id")
    if is_missing(exception_owner):
        errors.append(f"{row_id}: approved exception is missing exception_owner")
    if is_missing(reason):
        errors.append(f"{row_id}: approved exception is missing blocker_reason, actual_result, or notes")
    expiry = parse_exception_expiry(exception_expires)
    if is_missing(exception_expires) or expiry is None:
        errors.append(f"{row_id}: approved exception is missing a YYYY-MM-DD or ISO-8601 exception_expires")
    elif expiry < datetime.now(timezone.utc).date():
        errors.append(f"{row_id}: approved exception expired on {expiry.isoformat()}")
    return errors


def validate_matrix(
    matrix_path: Path,
    manifest_path: Path,
    repo_root: Path,
    max_errors: int,
    require_pass: bool,
    allow_approved_exceptions: bool,
) -> int:
    if not matrix_path.exists():
        raise SystemExit(
            f"release matrix not found: {matrix_path}\n"
            "Generate release evidence first, for example with `make release-security-scan`, "
            "or pass --matrix and --manifest for a generated artifact matrix."
        )
    manifest = load_manifest(manifest_path)
    counts: Counter[str] = Counter()
    errors: list[str] = []
    hash_cache: dict[Path, str] = {}
    matrix_row_ids: set[str] = set()

    with matrix_path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        fieldnames = set(reader.fieldnames or [])
        required = {"row_id", "evidence_ref", "evidence_sha256", "source_commit", "blocker_reason"}
        missing = sorted(required - set(reader.fieldnames or []))
        if missing:
            raise SystemExit(f"matrix is missing required columns: {', '.join(missing)}")
        if not {"readiness_status", "result", "status"} & fieldnames:
            raise SystemExit("matrix is missing a status column: readiness_status, result, or status")

        for row in reader:
            status = status_for_row(row)
            counts[status] += 1
            row_id = row.get("row_id", "").strip()
            display_row_id = row_id or "<missing-row-id>"
            row_errors: list[str] = []

            if not row_id:
                row_errors.append("<missing-row-id>: row_id is missing")
            elif row_id in matrix_row_ids:
                row_errors.append(f"{row_id}: duplicate row_id in matrix")
            else:
                matrix_row_ids.add(row_id)

            if status == PASS:
                row_errors.extend(validate_pass_row(row, manifest, repo_root, hash_cache))
            elif status == BLOCKED:
                reason = row.get("blocker_reason", "").strip()
                if not reason or reason in {"NONE", "NOT_APPLICABLE", "TBD"}:
                    row_errors.append(f"{display_row_id}: BLOCKED row is missing blocker_reason")
            elif status == FAIL:
                actual = row.get("actual_result", "").strip()
                if not actual or actual in {"NONE", "NOT_APPLICABLE", "TBD"}:
                    row_errors.append(f"{display_row_id}: FAIL row is missing actual_result")
            elif status == SKIPPED:
                pass
            else:
                row_errors.append(f"{display_row_id}: unsupported status {status or '<blank>'}")

            if require_pass and status != PASS:
                if allow_approved_exceptions:
                    row_errors.extend(validate_approved_exception(row, display_row_id))
                else:
                    row_errors.append(f"{display_row_id}: {status or '<blank>'} row is not allowed by --require-pass")

            if len(errors) < max_errors:
                errors.extend(row_errors[: max_errors - len(errors)])

    if len(errors) < max_errors:
        coverage_errors = validate_manifest_row_coverage(manifest, matrix_row_ids)
        errors.extend(coverage_errors[: max_errors - len(errors)])

    print("matrix status counts:")
    for status, count in sorted(counts.items()):
        print(f"  {status or '<blank>'}: {count}")

    if errors:
        print("release matrix validation failed:", file=sys.stderr)
        for error in errors[:max_errors]:
            print(f"  - {error}", file=sys.stderr)
        if len(errors) >= max_errors:
            print(f"  - stopped after {max_errors} errors", file=sys.stderr)
        return 1

    print("release matrix validation ok")
    return 0


def current_commit(repo_root: Path) -> str:
    git_dir = repo_root / ".git"
    if not git_dir.exists():
        return ""
    import subprocess

    try:
        return subprocess.check_output(
            ["git", "rev-parse", "HEAD"],
            cwd=repo_root,
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except (OSError, subprocess.CalledProcessError):
        return ""


def generate_manifest(evidence_root: Path, output: Path, repo_root: Path, source_commit: str, result: str) -> int:
    if not evidence_root.exists():
        raise SystemExit(f"evidence root not found: {evidence_root}")
    repo_relative(evidence_root, repo_root, "evidence root")
    repo_relative(output, repo_root, "manifest output")
    entries: list[dict[str, Any]] = []
    for path in sorted(evidence_root.rglob("*")):
        if path.is_symlink():
            raise SystemExit(f"evidence path must not be a symlink: {path}")
        if not path.is_file():
            continue
        evidence_ref = repo_relative(path, repo_root, "evidence path")
        entries.append(
            {
                "evidence_id": evidence_ref,
                "evidence_ref": evidence_ref,
                "artifact_path": evidence_ref,
                "sha256": file_sha256(path),
                "source_commit": source_commit,
                "result": result,
                "rows": [],
            }
        )

    payload = {
        "schema_version": 1,
        "generated_at_utc": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "evidence": entries,
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"wrote evidence manifest entries={len(entries)} path={output}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate enterprise release matrix evidence.")
    parser.add_argument(
        "--matrix",
        help=f"release matrix CSV to validate (default: {DEFAULT_VALIDATION_MATRIX})",
    )
    parser.add_argument(
        "--manifest",
        help=(
            f"evidence manifest JSON to validate (default: {DEFAULT_VALIDATION_MANIFEST}; "
            f"default with --generate-manifest: {DEFAULT_GENERATED_MANIFEST})"
        ),
    )
    parser.add_argument("--repo-root", default=".")
    parser.add_argument("--max-errors", type=int, default=50)
    parser.add_argument("--require-pass", action="store_true")
    parser.add_argument(
        "--allow-approved-exceptions",
        action="store_true",
        help=(
            "with --require-pass, allow non-pass rows only when exception_id, "
            "exception_owner, exception_expires, and an exception reason are complete and unexpired"
        ),
    )
    parser.add_argument("--generate-manifest", action="store_true")
    parser.add_argument("--evidence-root", default="docs/release/enterprise-release-evidence")
    parser.add_argument("--source-commit")
    parser.add_argument(
        "--manifest-result",
        default="TODO",
        help="result value stamped into generated manifest entries; use pass only for reviewed evidence",
    )
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    if args.generate_manifest:
        manifest_path = (repo_root / (args.manifest or DEFAULT_GENERATED_MANIFEST)).resolve()
        source_commit = args.source_commit or current_commit(repo_root)
        return generate_manifest(
            evidence_root=(repo_root / args.evidence_root).resolve(),
            output=manifest_path,
            repo_root=repo_root,
            source_commit=source_commit,
            result=args.manifest_result,
        )

    matrix_path = (repo_root / (args.matrix or DEFAULT_VALIDATION_MATRIX)).resolve()
    manifest_path = (repo_root / (args.manifest or DEFAULT_VALIDATION_MANIFEST)).resolve()
    return validate_matrix(
        matrix_path=matrix_path,
        manifest_path=manifest_path,
        repo_root=repo_root,
        max_errors=max(1, args.max_errors),
        require_pass=args.require_pass,
        allow_approved_exceptions=args.allow_approved_exceptions,
    )


if __name__ == "__main__":
    sys.exit(main())
