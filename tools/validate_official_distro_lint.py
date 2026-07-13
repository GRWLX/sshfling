#!/usr/bin/env python3
"""Validate official distro lint outputs.

The packaging drafts still have external blockers: the project license,
placeholder Debian maintainer identity, unsigned local RPMs, and the missing
initial Debian ITP/RFS bug. This tool lets CI fail on any new lint issue while
keeping those known blockers explicit in the readiness report.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


ALLOWED_LINTIAN_TAGS = {
    "bogus-mail-host",
    "bogus-mail-host-in-debian-changelog",
    "initial-upload-closes-no-bugs",
    "root-in-contact",
}

LINTIAN_LINE = re.compile(r"^[EWIPX]:\s+.+?:\s+([a-z0-9][a-z0-9+.-]*)\b")


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def lintian_tags(text: str) -> list[tuple[str, str]]:
    tags: list[tuple[str, str]] = []
    for line in text.splitlines():
        match = LINTIAN_LINE.match(line)
        if match:
            tags.append((match.group(1), line))
    return tags


def validate_lintian(path: Path, exit_code: int = 0) -> int:
    tags = lintian_tags(read_text(path))
    if exit_code != 0 and not tags:
        print(f"lintian exited {exit_code} without parseable tags: {path}", file=sys.stderr)
        return 1
    unexpected = [(tag, line) for tag, line in tags if tag not in ALLOWED_LINTIAN_TAGS]
    if unexpected:
        print(f"unexpected lintian issue(s) in {path}:", file=sys.stderr)
        for _tag, line in unexpected:
            print(line, file=sys.stderr)
        return 1
    print(f"lintian validation ok: {len(tags)} known external blocker(s)")
    return 0


def autopkgtest_results(text: str) -> list[tuple[str, str, str]]:
    results: list[tuple[str, str, str]] = []
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        parts = stripped.split(None, 2)
        if len(parts) >= 2:
            details = parts[2] if len(parts) > 2 else ""
            results.append((parts[0], parts[1], details))
    return results


def validate_autopkgtest(path: Path, exit_code: int) -> int:
    results = autopkgtest_results(read_text(path))
    if not results:
        print(f"autopkgtest summary is empty: {path}", file=sys.stderr)
        return 1
    failing = [result for result in results if result[1] != "PASS"]
    if failing:
        print(f"autopkgtest failure(s) in {path}:", file=sys.stderr)
        for name, status, details in failing:
            print(f"{name} {status} {details}".rstrip(), file=sys.stderr)
        return 1
    if exit_code != 0:
        print(f"autopkgtest summary passed; backend exited {exit_code}")
    print(f"autopkgtest validation ok: {len(results)} test(s) passed")
    return 0


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    lintian = subparsers.add_parser("lintian", help="Validate lintian output.")
    lintian.add_argument("report", type=Path)
    lintian.add_argument("--exit-code", type=int, default=0)

    autopkgtest = subparsers.add_parser("autopkgtest", help="Validate an autopkgtest summary.")
    autopkgtest.add_argument("summary", type=Path)
    autopkgtest.add_argument("--exit-code", type=int, default=0)

    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    if args.command == "lintian":
        return validate_lintian(args.report, args.exit_code)
    if args.command == "autopkgtest":
        return validate_autopkgtest(args.summary, args.exit_code)
    raise AssertionError(args.command)


if __name__ == "__main__":
    raise SystemExit(main())
