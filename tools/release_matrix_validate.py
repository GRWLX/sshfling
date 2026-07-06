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
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
PASS = "PASS"
FAIL = "FAIL"
BLOCKED = "BLOCKED"
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
    rows = entry.get("rows") or entry.get("row_ids") or entry.get("row_id")
    row_id = row.get("row_id", "")
    if isinstance(rows, str):
        return bool(rows) and rows == row_id
    if isinstance(rows, list):
        return row_id in {str(item) for item in rows}
    return False


def validate_pass_row(
    row: dict[str, str],
    manifest: dict[str, dict[str, Any]],
    repo_root: Path,
    hash_cache: dict[Path, str],
) -> list[str]:
    errors: list[str] = []
    row_id = row.get("row_id", "<missing-row-id>")
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
        local_path = (repo_root / artifact_path).resolve()
        try:
            local_path.relative_to(repo_root.resolve())
        except ValueError:
            errors.append(f"{row_id}: manifest artifact path escapes repo: {artifact_path}")
        else:
            if not local_path.exists():
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


def validate_matrix(matrix_path: Path, manifest_path: Path, repo_root: Path, max_errors: int) -> int:
    manifest = load_manifest(manifest_path)
    counts: Counter[str] = Counter()
    errors: list[str] = []
    hash_cache: dict[Path, str] = {}

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
            row_id = row.get("row_id", "<missing-row-id>")
            row_errors: list[str] = []

            if status == PASS:
                row_errors.extend(validate_pass_row(row, manifest, repo_root, hash_cache))
            elif status == BLOCKED:
                reason = row.get("blocker_reason", "").strip()
                if not reason or reason in {"NONE", "NOT_APPLICABLE", "TBD"}:
                    row_errors.append(f"{row_id}: BLOCKED row is missing blocker_reason")
            elif status == FAIL:
                actual = row.get("actual_result", "").strip()
                if not actual or actual in {"NONE", "NOT_APPLICABLE", "TBD"}:
                    row_errors.append(f"{row_id}: FAIL row is missing actual_result")

            if len(errors) < max_errors:
                errors.extend(row_errors[: max_errors - len(errors)])

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
            ["git", "rev-parse", "--short=12", "HEAD"],
            cwd=repo_root,
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except (OSError, subprocess.CalledProcessError):
        return ""


def generate_manifest(evidence_root: Path, output: Path, repo_root: Path, source_commit: str, result: str) -> int:
    if not evidence_root.exists():
        raise SystemExit(f"evidence root not found: {evidence_root}")
    entries: list[dict[str, Any]] = []
    for path in sorted(evidence_root.rglob("*")):
        if not path.is_file():
            continue
        evidence_ref = path.resolve().relative_to(repo_root.resolve()).as_posix()
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
    parser.add_argument("--matrix", default="docs/release/enterprise-release-matrix.csv")
    parser.add_argument("--manifest", default="docs/release/evidence-manifest.json")
    parser.add_argument("--repo-root", default=".")
    parser.add_argument("--max-errors", type=int, default=50)
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
    manifest_path = (repo_root / args.manifest).resolve()
    if args.generate_manifest:
        source_commit = args.source_commit or current_commit(repo_root)
        return generate_manifest(
            evidence_root=(repo_root / args.evidence_root).resolve(),
            output=manifest_path,
            repo_root=repo_root,
            source_commit=source_commit,
            result=args.manifest_result,
        )

    return validate_matrix(
        matrix_path=(repo_root / args.matrix).resolve(),
        manifest_path=manifest_path,
        repo_root=repo_root,
        max_errors=max(1, args.max_errors),
    )


if __name__ == "__main__":
    sys.exit(main())
