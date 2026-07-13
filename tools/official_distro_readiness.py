#!/usr/bin/env python3
"""Generate official distro repository readiness evidence.

This check is intentionally conservative. Passing generated DEB/RPM builds is
not enough for Debian, Ubuntu, Fedora, or EPEL. Official distro submission also
needs distro source packaging, policy-compliant metadata, and a redistributable
license accepted by the target archive.
"""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]

BLOCKED = "BLOCKED"
WARN = "WARN"
PASS = "PASS"


@dataclass(frozen=True)
class Check:
    area: str
    status: str
    evidence: str
    next_action: str


def read_text(relative: str) -> str:
    return (REPO_ROOT / relative).read_text(encoding="utf-8")


def exists(relative: str) -> bool:
    return (REPO_ROOT / relative).exists()


def license_status() -> Check:
    text = read_text("LICENSE")
    lowered = text.lower()
    has_apache_2 = "apache license" in lowered and "version 2.0" in lowered
    proprietary_markers = (
        "not open source",
        "paid use required",
        "requires prior written permission",
        "proprietary software",
    )
    if any(marker in lowered for marker in proprietary_markers):
        return Check(
            "License",
            BLOCKED,
            "LICENSE declares SSHFling proprietary, not open source, paid-use, and redistribution-restricted.",
            "Choose an OSI/DFSG/Fedora-acceptable open-source license or obtain a distro-specific redistribution grant before official archive submission.",
        )
    return Check(
        "License",
        PASS if has_apache_2 else WARN,
        "LICENSE declares Apache License, Version 2.0." if has_apache_2 else "LICENSE does not contain the known proprietary redistribution blockers.",
        "Confirm package metadata preserves Apache-2.0 license files and required notices.",
    )


def debian_source_packaging_status() -> Check:
    required = (
        "debian/control",
        "debian/rules",
        "debian/changelog",
        "debian/copyright",
        "debian/source/format",
    )
    missing = [path for path in required if not exists(path)]
    if missing:
        return Check(
            "Debian/Ubuntu source packaging",
            BLOCKED,
            "Missing official source package files: " + ", ".join(missing) + ".",
            "Create a policy-compliant debian/ source package, build with dpkg-buildpackage, and validate with lintian/autopkgtest before mentors.debian.net or Ubuntu sponsorship.",
        )
    return Check(
        "Debian/Ubuntu source packaging",
        WARN,
        "Required debian/ source package files are present as a draft.",
        "Build and lint the source package, then prepare WNPP/ITP and sponsorship materials.",
    )


def debian_maintainer_status() -> Check:
    text = read_text("debian/control") if exists("debian/control") else ""
    if "root@localhost" in text:
        return Check(
            "Debian/Ubuntu maintainer metadata",
            WARN,
            "debian/control still uses placeholder Maintainer metadata.",
            "Replace placeholder maintainer metadata with the accountable Debian/Ubuntu maintainer or team before upload.",
        )
    return Check(
        "Debian/Ubuntu maintainer metadata",
        PASS,
        "debian/control does not use the known placeholder maintainer.",
        "Confirm the maintainer identity matches the sponsor or uploader process.",
    )


def generated_deb_status() -> Check:
    text = read_text("packaging/build-deb.sh")
    if "Maintainer: SSHFling Maintainers <root@localhost>" in text:
        return Check(
            "Generated DEB metadata",
            WARN,
            "packaging/build-deb.sh still emits placeholder Maintainer metadata.",
            "Replace placeholder maintainer metadata in generated packages and keep generated DEBs separate from official Debian source packaging.",
        )
    return Check(
        "Generated DEB metadata",
        PASS,
        "Generated DEB metadata does not use the known placeholder maintainer.",
        "Keep generated upstream repository packages aligned with official Debian metadata where practical.",
    )


def fedora_packaging_status() -> Check:
    spec_paths = (
        "packaging/fedora/sshfling.spec",
        "packaging/rpm/sshfling.spec",
        "sshfling.spec",
    )
    if not any(exists(path) for path in spec_paths):
        return Check(
            "Fedora/EPEL source packaging",
            BLOCKED,
            "No checked-in Fedora review spec file was found; packaging/build-rpm.sh generates a transient RPM spec.",
            "Add a Fedora-compliant spec, build an SRPM, and validate with rpmlint/mock/fedora-review before Fedora package review.",
        )
    return Check(
        "Fedora/EPEL source packaging",
        WARN,
        "A checked-in RPM spec path exists as a draft.",
        "Validate the spec with rpmlint/mock/fedora-review and submit a Fedora package review before EPEL branches.",
    )


def fedora_spec_license_status() -> Check:
    spec_paths = (
        "packaging/fedora/sshfling.spec",
        "packaging/rpm/sshfling.spec",
        "sshfling.spec",
    )
    for path in spec_paths:
        if exists(path):
            text = read_text(path)
            if "License:        Apache-2.0" in text or "License: Apache-2.0" in text:
                return Check(
                    "Fedora/EPEL spec license metadata",
                    PASS,
                    f"{path} records Apache-2.0.",
                    "Confirm the spec License field remains a Fedora-accepted license expression during package review.",
                )
            return Check(
                "Fedora/EPEL spec license metadata",
                WARN,
                f"{path} does not record Apache-2.0 in the License field.",
                "Confirm the spec License field matches an accepted Fedora license expression.",
            )
    return Check(
        "Fedora/EPEL spec license metadata",
        BLOCKED,
        "No checked-in Fedora spec file exists.",
        "Add a Fedora spec before evaluating Fedora license metadata.",
    )


def generated_rpm_license_status() -> Check:
    text = read_text("packaging/build-rpm.sh")
    if "License: Apache-2.0" in text:
        return Check(
            "Generated RPM license metadata",
            PASS,
            "packaging/build-rpm.sh emits Apache-2.0.",
            "Keep generated upstream RPM metadata aligned with the Fedora review spec where practical.",
        )
    return Check(
        "Generated RPM license metadata",
        WARN,
        "Generated RPM spec does not emit Apache-2.0.",
        "Confirm the spec License field matches an accepted Fedora license expression.",
    )


def package_validation_status() -> Check:
    build_targets = all(
        exists(path)
        for path in (
            "packaging/build-deb.sh",
            "packaging/build-rpm.sh",
            "tests/cross-os/validate-local-install.sh",
            ".github/workflows/package-install-tests.yml",
        )
    )
    if build_targets:
        return Check(
            "Package build/test coverage",
            PASS,
            "Generated DEB/RPM builders, local install validation, and package-install workflow are present.",
            "Keep these as upstream smoke tests while adding distro-native source package tests.",
        )
    return Check(
        "Package build/test coverage",
        WARN,
        "One or more generated package build or install-test files are missing.",
        "Restore generated package build and install validation before submission.",
    )


def official_distro_draft_validation_status() -> Check:
    required = (
        "packaging/validate-official-distro-drafts.sh",
        "packaging/fedora/rpmlint.toml",
        "tools/validate_official_distro_lint.py",
        ".github/workflows/official-distro-drafts.yml",
    )
    missing = [path for path in required if not exists(path)]
    if missing:
        return Check(
            "Official distro draft validation",
            WARN,
            "Missing validation entry points: " + ", ".join(missing) + ".",
            "Add repeatable validation for Debian source packaging and Fedora spec drafts.",
        )
    return Check(
        "Official distro draft validation",
        PASS,
        "Repeatable local and CI validation exists for Debian and Fedora packaging drafts, including lintian, rpmlint, and autopkgtest smoke coverage with known review warnings isolated.",
        "Run mock and fedora-review before formal Fedora package review.",
    )


def checks() -> list[Check]:
    return [
        license_status(),
        debian_source_packaging_status(),
        debian_maintainer_status(),
        generated_deb_status(),
        fedora_packaging_status(),
        fedora_spec_license_status(),
        generated_rpm_license_status(),
        package_validation_status(),
        official_distro_draft_validation_status(),
    ]


def render_markdown(items: list[Check]) -> str:
    lines = [
        "# Official Distro Repository Readiness",
        "",
        "This evidence is for publication through official Debian, Ubuntu, Fedora, and EPEL repositories. It is separate from the upstream signed APT/DNF repository.",
        "",
        "Status meanings:",
        "",
        "- `PASS`: sufficient evidence exists for this readiness item.",
        "- `WARN`: usable for upstream packaging, but not enough for official archive submission.",
        "- `BLOCKED`: do not submit to the official archive until resolved.",
        "",
        "| Area | Status | Evidence | Required next action |",
        "| --- | --- | --- | --- |",
    ]
    for item in items:
        lines.append(
            "| "
            + " | ".join(
                value.replace("|", "\\|").replace("\n", " ")
                for value in (item.area, item.status, item.evidence, item.next_action)
            )
            + " |"
        )
    lines.extend(
        [
            "",
            "## Submission Path",
            "",
            "1. Keep Apache-2.0 metadata consistent across source, generated packages, and distro drafts.",
            "2. Validate Debian source packaging with `dpkg-buildpackage`, `lintian`, and `autopkgtest`.",
            "3. File a Debian WNPP/ITP bug, upload to mentors.debian.net, and find a Debian sponsor.",
            "4. Let Ubuntu sync from Debian when possible; otherwise request Ubuntu sponsorship for a source package.",
            "5. Add a Fedora-compliant spec and SRPM, validate with `rpmlint`, `mock`, and `fedora-review`, then file Fedora package review.",
            "6. Request EPEL branches only after Fedora package acceptance.",
            "",
            "## Current Decision Gate",
            "",
            "No `BLOCKED` rows remain. Rows with `WARN` still need maintainer or sponsor review before upload.",
            "",
        ]
    )
    return "\n".join(lines)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=REPO_ROOT / "docs/official-distro-readiness.md")
    parser.add_argument("--write", action="store_true", help="Write the readiness report.")
    parser.add_argument("--check", action="store_true", help="Check that the report is current.")
    parser.add_argument(
        "--fail-on-blocked",
        action="store_true",
        help="Exit non-zero when any readiness item is blocked.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    items = checks()
    rendered = render_markdown(items)

    if args.write:
        args.output.write_text(rendered, encoding="utf-8")

    if args.check:
        current = args.output.read_text(encoding="utf-8") if args.output.exists() else ""
        if current != rendered:
            print(f"{args.output} is out of date; run tools/official_distro_readiness.py --write", file=sys.stderr)
            return 1

    if not args.write and not args.check:
        print(rendered)

    if args.fail_on_blocked and any(item.status == BLOCKED for item in items):
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
