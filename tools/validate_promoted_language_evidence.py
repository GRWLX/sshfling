#!/usr/bin/env python3
"""Fail unless every newly promoted language has explicit runtime PASS evidence."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path


FUNCTIONAL_LANGUAGES = ("julia", "j", "janet")
SYSTEM_LANGUAGES = ("v", "webassembly-wasi", "odin", "pony")
SYSTEM_BUILD_LANGUAGES = ("zig",)
SYSTEM_LIFECYCLE_PHASES = (
    "source-archive",
    "install",
    "isolated-consumer",
    "cli-version",
    "init-template",
    "invalid-option",
    "missing-runtime",
    "uninstall",
    "uninstall-import",
    "runtime-validation",
)


def read_functional(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as stream:
        return list(csv.DictReader(stream, delimiter="\t"))


def read_systems(path: Path) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    with path.open(encoding="utf-8", newline="") as stream:
        reader = csv.reader(stream, delimiter="\t")
        header = next(reader, None)
        if header != ["record", "subject", "phase", "status", "detail"]:
            raise ValueError(f"{path}: invalid systems evidence header")
        for row in reader:
            if len(row) != 5:
                raise ValueError(f"{path}: invalid systems evidence row: {row!r}")
            rows.append(dict(zip(header, row, strict=True)))
    return rows


def detail_fields(detail: str) -> dict[str, str]:
    fields: dict[str, str] = {}
    for item in detail.split(";"):
        if "=" in item:
            key, value = item.split("=", 1)
            fields[key] = value
    return fields


def validate(functional_path: Path, systems_path: Path, version: str) -> list[str]:
    errors: list[str] = []
    functional = read_functional(functional_path)
    systems = read_systems(systems_path)

    canonical = [
        row
        for row in functional
        if row.get("language") == "validator" and row.get("phase") == "canonical-runtime"
    ]
    if len(canonical) != 1 or canonical[0].get("result") != "PASS":
        errors.append("functional evidence lacks exactly one canonical runtime PASS")
    elif detail_fields(canonical[0].get("detail", "")).get("version") != version:
        errors.append(f"functional canonical runtime version is not {version}")

    for language in FUNCTIONAL_LANGUAGES:
        selected = [row for row in functional if row.get("language") == language]
        outcomes = [row for row in selected if row.get("phase") == "outcome"]
        if len(outcomes) != 1 or outcomes[0].get("result") != "PASS":
            errors.append(f"{language}: expected exactly one functional PASS outcome")
            continue
        detail = outcomes[0].get("detail", "")
        for capability in ("archive=yes", "install=yes", "consumer=yes", "remove=yes"):
            if capability not in detail:
                errors.append(f"{language}: PASS outcome lacks {capability}")
        bundles = [row for row in selected if row.get("phase") == "canonical-bundle"]
        if (
            len(bundles) != 1
            or bundles[0].get("result") != "PASS"
            or detail_fields(bundles[0].get("detail", "")).get("version") != version
        ):
            errors.append(f"{language}: canonical bundle is not version {version}")
        version_outputs = [row for row in selected if row.get("phase") == "exact-version-output"]
        expected_output = f"sshfling {version}"
        if not version_outputs or any(
            row.get("result") != "PASS"
            or row.get("status") != "0"
            or detail_fields(row.get("detail", "")).get("expected") != expected_output
            or detail_fields(row.get("detail", "")).get("actual") != expected_output
            for row in version_outputs
        ):
            errors.append(f"{language}: lacks exact version {version} output evidence")
        if any(row.get("result") in {"FAIL", "BLOCKED"} for row in selected):
            errors.append(f"{language}: contradictory functional FAIL/BLOCKED evidence")

    source_versions = [
        row
        for row in systems
        if row.get("subject") == "batch" and row.get("phase") == "source-version"
    ]
    if (
        len(source_versions) != 1
        or source_versions[0].get("status") != "PASS"
        or detail_fields(source_versions[0].get("detail", "")).get("version") != version
    ):
        errors.append(f"systems source version is not {version}")

    for language in SYSTEM_LANGUAGES:
        selected = [row for row in systems if row.get("subject") == language]
        by_phase = {row.get("phase"): row.get("status") for row in selected}
        details = {row.get("phase"): row.get("detail", "") for row in selected}
        for phase in SYSTEM_LIFECYCLE_PHASES:
            if by_phase.get(phase) != "PASS":
                errors.append(f"{language}: {phase} is not PASS")
        for phase in ("isolated-consumer", "cli-version"):
            output = detail_fields(details.get(phase, "")).get("output")
            if output != f"sshfling {version}":
                errors.append(f"{language}: {phase} output is not sshfling {version}")
        if any(row.get("status") in {"FAIL", "BLOCKED", "INCOMPLETE"} for row in selected):
            errors.append(f"{language}: contradictory systems failure evidence")

    for language in SYSTEM_BUILD_LANGUAGES:
        selected = [row for row in systems if row.get("subject") == language]
        required_phases = (
            "source-archive",
            "cli-version",
            "init-template",
            "invalid-option",
            "missing-runtime",
            "runtime-validation",
        )
        by_phase: dict[str, dict[str, str]] = {}
        for phase in required_phases:
            phase_rows = [row for row in selected if row.get("phase") == phase]
            if len(phase_rows) != 1 or phase_rows[0].get("status") != "PASS":
                errors.append(f"{language}: {phase} is not PASS")
            elif len(phase_rows) == 1:
                by_phase[phase] = phase_rows[0]
        if any(row.get("status") in {"FAIL", "BLOCKED", "INCOMPLETE"} for row in selected):
            errors.append(f"{language}: contradictory systems failure evidence")
        output = detail_fields(by_phase.get("cli-version", {}).get("detail", "")).get("output")
        if output != f"sshfling {version}":
            errors.append(f"{language}: cli-version output is not sshfling {version}")
        runtime_detail = by_phase.get("runtime-validation", {}).get("detail", "")
        if "mode=build-only" not in runtime_detail:
            errors.append(f"{language}: runtime evidence does not declare build-only mode")

    return errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--functional", type=Path, required=True)
    parser.add_argument("--systems", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        errors = validate(args.functional, args.systems, args.version)
    except (OSError, ValueError) as exc:
        print(exc)
        return 1
    if errors:
        for error in errors:
            print(error)
        return 1
    print("promoted language runtime evidence validated")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
