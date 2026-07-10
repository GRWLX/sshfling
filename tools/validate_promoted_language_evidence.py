#!/usr/bin/env python3
"""Fail unless every newly promoted language has explicit runtime PASS evidence."""

from __future__ import annotations

import argparse
import csv
import re
from pathlib import Path


FUNCTIONAL_LANGUAGES = ("julia", "j", "janet", "ring", "ballerina")
SCRIPTING_LANGUAGES = ("guix-scheme",)
SCRIPTING_LIFECYCLE_PHASES = (
    "package-archive",
    "package-cli-version",
    "package-cli-init-assets",
    "symlink-cli-version",
    "guile-runtime",
    "guix-definition",
    "removal",
    "removal-source",
)
SYSTEM_LANGUAGES = ("v", "webassembly-wasi", "odin", "pony", "swift", "chapel")
SYSTEM_BUILD_LANGUAGES = ("zig", "harbour", "red", "object-pascal")
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
SYSTEM_LIFECYCLE_CAPABILITIES = {
    "v": (
        "compile",
        "library-consumer",
        "cli-runtime",
        "init-workflow",
        "exit-workflow",
        "archive-install",
        "isolated-consumer",
        "remove",
        "post-removal-import-failure",
    ),
    "webassembly-wasi": (
        "compile",
        "library-build",
        "library-consumer",
        "cli-runtime",
        "init-workflow",
        "exit-workflow",
        "archive-install",
        "isolated-consumer",
        "remove",
        "post-removal-import-failure",
    ),
    "odin": (
        "compile",
        "library-build",
        "library-consumer",
        "cli-runtime",
        "init-workflow",
        "exit-workflow",
        "archive-install",
        "isolated-consumer",
        "remove",
        "post-removal-import-failure",
    ),
    "pony": (
        "compile",
        "library-build",
        "library-consumer",
        "cli-runtime",
        "init-workflow",
        "exit-workflow",
        "archive-install",
        "isolated-consumer",
        "remove",
        "post-removal-import-failure",
    ),
    "swift": (
        "compile",
        "library-consumer",
        "cli-runtime",
        "init-workflow",
        "exit-workflow",
        "archive-install",
        "isolated-consumer",
        "remove",
        "post-removal-import-failure",
    ),
    "chapel": (
        "compile",
        "library-consumer",
        "cli-runtime",
        "init-workflow",
        "exit-workflow",
        "archive-install",
        "isolated-consumer",
        "remove",
        "post-removal-import-failure",
    ),
}


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


def read_scripting(path: Path) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    with path.open(encoding="utf-8", newline="") as stream:
        reader = csv.reader(stream, delimiter="\t")
        for row in reader:
            if len(row) != 5:
                raise ValueError(f"{path}: invalid scripting evidence row: {row!r}")
            record, subject, phase, status, detail = row
            rows.append(
                {
                    "record": record,
                    "subject": subject,
                    "phase": phase,
                    "status": status,
                    "detail": detail,
                }
            )
    return rows


def detail_fields(detail: str) -> dict[str, str]:
    fields: dict[str, str] = {}
    for item in detail.split(";"):
        if "=" in item:
            key, value = item.split("=", 1)
            fields[key] = value
    return fields


def validate(
    functional_path: Path,
    systems_path: Path,
    scripting_path: Path,
    version: str,
) -> list[str]:
    errors: list[str] = []
    functional = read_functional(functional_path)
    systems = read_systems(systems_path)
    scripting = read_scripting(scripting_path)

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

    scripting_versions = [
        row
        for row in scripting
        if row.get("subject") == "batch" and row.get("phase") == "source-version"
    ]
    if (
        len(scripting_versions) != 1
        or scripting_versions[0].get("status") != "PASS"
        or scripting_versions[0].get("detail") != version
    ):
        errors.append(f"scripting source version is not {version}")

    for language in SCRIPTING_LANGUAGES:
        selected = [row for row in scripting if row.get("subject") == language]
        by_phase: dict[str, dict[str, str]] = {}
        for phase in SCRIPTING_LIFECYCLE_PHASES:
            phase_rows = [row for row in selected if row.get("phase") == phase]
            if len(phase_rows) != 1 or phase_rows[0].get("status") != "PASS":
                errors.append(f"{language}: {phase} is not PASS")
            elif len(phase_rows) == 1:
                by_phase[phase] = phase_rows[0]
        archive = detail_fields(by_phase.get("package-archive", {}).get("detail", ""))
        if archive.get("artifact") != f"sshfling-{language}-{version}.tar.gz":
            errors.append(f"{language}: package archive is not version {version}")
        if archive.get("repeat_build") != "identical":
            errors.append(f"{language}: package archive is not reproducible")
        if not re.fullmatch(r"[0-9a-f]{64}", archive.get("sha256", "")):
            errors.append(f"{language}: package archive lacks a valid sha256")
        for phase in ("package-cli-version", "symlink-cli-version", "guile-runtime"):
            detail = by_phase.get(phase, {}).get("detail", "")
            if f"sshfling {version}" not in detail:
                errors.append(f"{language}: {phase} output is not sshfling {version}")
        if by_phase.get("guix-definition", {}).get("detail") != "guix-dry-run":
            errors.append(f"{language}: guix package-definition evidence is not dry-run")
        if "absent" not in by_phase.get("removal-source", {}).get("detail", ""):
            errors.append(f"{language}: removal evidence does not prove source absence")
        if any(row.get("status") in {"FAIL", "BLOCKED", "INCOMPLETE", "SKIP"} for row in selected):
            errors.append(f"{language}: contradictory scripting failure evidence")

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
        by_phase: dict[str, dict[str, str]] = {}
        for phase in SYSTEM_LIFECYCLE_PHASES:
            phase_rows = [row for row in selected if row.get("phase") == phase]
            if len(phase_rows) != 1 or phase_rows[0].get("status") != "PASS":
                errors.append(f"{language}: {phase} is not PASS")
            elif len(phase_rows) == 1:
                by_phase[phase] = phase_rows[0]
        for phase in ("isolated-consumer", "cli-version"):
            output = detail_fields(by_phase.get(phase, {}).get("detail", "")).get("output")
            if output != f"sshfling {version}":
                errors.append(f"{language}: {phase} output is not sshfling {version}")

        archive = detail_fields(by_phase.get("source-archive", {}).get("detail", ""))
        if archive.get("artifact") != f"sshfling-{language}-{version}.tar.gz":
            errors.append(f"{language}: source archive is not version {version}")
        if archive.get("repeat_build") != "identical":
            errors.append(f"{language}: source archive is not reproducible")
        if not archive.get("files", "").isdigit() or int(archive["files"]) < 1:
            errors.append(f"{language}: source archive has no file inventory")
        for digest in ("sha256", "inventory_sha256"):
            if not re.fullmatch(r"[0-9a-f]{64}", archive.get(digest, "")):
                errors.append(f"{language}: source archive lacks a valid {digest}")

        install = detail_fields(by_phase.get("install", {}).get("detail", ""))
        if install.get("source_archive_extracted") != "yes":
            errors.append(f"{language}: install does not extract the source archive")

        runtime = detail_fields(by_phase.get("runtime-validation", {}).get("detail", ""))
        if runtime.get("builder_exit") != "0" or runtime.get("mode") != "archive-lifecycle":
            errors.append(f"{language}: runtime evidence is not a successful archive lifecycle")
        capabilities = tuple(filter(None, runtime.get("capabilities", "").split(",")))
        if capabilities != SYSTEM_LIFECYCLE_CAPABILITIES[language]:
            errors.append(f"{language}: runtime capability evidence is incomplete")

        if language == "swift":
            consumer = detail_fields(
                by_phase.get("isolated-consumer", {}).get("detail", "")
            )
            if (
                consumer.get("swiftpm_local_dependency") != "yes"
                or consumer.get("package_version") != version
                or consumer.get("runtime_version") != version
            ):
                errors.append("swift: isolated consumer lacks versioned SwiftPM evidence")
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
    parser.add_argument("--scripting", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        errors = validate(args.functional, args.systems, args.scripting, args.version)
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
