from __future__ import annotations

import csv
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from contextlib import contextmanager
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "packaging" / "build-systems-languages.sh"
VERSION = re.search(
    r'^VERSION\s*=\s*["\']([^"\']+)["\']',
    (REPO_ROOT / "bin" / "sshfling").read_text(encoding="utf-8"),
    re.MULTILINE,
).group(1)

LIFECYCLE_CAPABILITIES = {
    "archive-install",
    "isolated-consumer",
    "remove",
    "post-removal-import-failure",
}
LIFECYCLE_LANGUAGES = {
    "v",
    "webassembly-wasi",
    "odin",
    "pony",
    "chapel",
    "swift",
}

FAKE_RUNTIME = r'''#!/usr/bin/env bash
set -euo pipefail
runtime="${SSHFLING_RUNTIME_DIR:-}"
if [[ ! -f "$runtime/sshfling.py" ]]; then
  exit 127
fi
case "${1:-}" in
  --version)
    printf 'sshfling @VERSION@\n'
    ;;
  init)
    project="${2:?missing project directory}"
    mkdir -p "$project/native" "$project/production"
    for executable in \
      "$project/native/sshfling-linux-account" \
      "$project/native/sshfling-unix-identity" \
      "$project/production/sshfling-login-shell"; do
      printf '#!/bin/sh\n' >"$executable"
      chmod 0755 "$executable"
    done
    : >"$project/README.md"
    : >"$project/compose.server.yml"
    printf 'SSH_SESSION_SECONDS=60\n' >"$project/.env"
    ;;
  --not-a-real-option)
    exit 2
    ;;
  @VERSION@)
    if [[ "${FAKE_BLANK_OUTPUT:-0}" != 1 ]]; then
      printf 'sshfling @VERSION@\n'
    fi
    ;;
  *)
    exit 2
    ;;
esac
'''.replace("@VERSION@", VERSION)

FAKE_COMPILER = r'''#!/usr/bin/env bash
set -euo pipefail
output=""
while (($# > 0)); do
  if [[ "$1" == "-o" ]]; then
    output="$2"
    shift 2
    continue
  fi
  shift
done
[[ -n "$output" ]]
mkdir -p "$(dirname "$output")"
case "$output" in
  *.a|*.o|*.so)
    printf 'fake compiler artifact\n' >"$output"
    ;;
  *)
    cat >"$output" <<'PROGRAM'
@RUNTIME@
PROGRAM
    chmod 0755 "$output"
    ;;
esac
'''.replace("@RUNTIME@", FAKE_RUNTIME.rstrip())

FAKE_ODIN = r'''#!/usr/bin/env bash
set -euo pipefail
collection=""
output=""
for argument in "$@"; do
  case "$argument" in
    -collection:sshfling=*) collection="${argument#*=}" ;;
    -out:*) output="${argument#-out:}" ;;
  esac
done
[[ -n "$output" ]]
if [[ -n "$collection" && ! -d "$collection" ]]; then
  exit 41
fi
mkdir -p "$(dirname "$output")"
cat >"$output" <<'PROGRAM'
@RUNTIME@
PROGRAM
chmod 0755 "$output"
'''.replace("@RUNTIME@", FAKE_RUNTIME.rstrip())


def parse_array(source: str, name: str) -> dict[str, str]:
    match = re.search(rf"declare -Ar {name}=\(\n(.*?)\n\)", source, re.DOTALL)
    if match is None:
        raise AssertionError(f"missing associative array: {name}")
    return dict(
        re.findall(r'^\s+\[([^]]+)]="([^"]*)"$', match.group(1), re.MULTILINE)
    )


def read_evidence(repo: Path) -> list[dict[str, str]]:
    evidence = repo / "dist" / f"sshfling-systems-languages-{VERSION}-validation.tsv"
    with evidence.open(encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle, delimiter="\t"))


def detail_fields(row: dict[str, str]) -> dict[str, str]:
    return dict(field.split("=", 1) for field in row["detail"].split(";") if field)


@contextmanager
def validator_fixture():
    with tempfile.TemporaryDirectory() as temporary:
        repo = Path(temporary) / "repo"
        (repo / "packaging").mkdir(parents=True)
        (repo / "bin").mkdir()

        for source in (SCRIPT, REPO_ROOT / "packaging" / "copy-templates.sh", REPO_ROOT / "packaging" / "version.sh"):
            shutil.copy2(source, repo / "packaging" / source.name)
        shutil.copytree(
            REPO_ROOT / "packaging" / "systems-languages",
            repo / "packaging" / "systems-languages",
        )
        shutil.copy2(REPO_ROOT / "bin" / "sshfling", repo / "bin" / "sshfling")

        for directory in (
            "scripts",
            "secrets",
            "ssh-client",
            "ssh-server",
            "production",
            "native",
            "systemd",
        ):
            shutil.copytree(REPO_ROOT / directory, repo / directory)
        for filename in (
            ".env.example",
            "LICENSE",
            "README.md",
            "compose.server.yml",
            "compose.client.yml",
        ):
            shutil.copy2(REPO_ROOT / filename, repo / filename)

        yield repo


def write_tool(path: Path, source: str) -> None:
    path.write_text(source, encoding="utf-8")
    path.chmod(0o755)


def run_validator(
    repo: Path,
    language: str,
    tools: dict[str, str],
    *,
    blank_output: bool = False,
) -> subprocess.CompletedProcess[str]:
    tool_dir = repo / "fake-bin"
    tool_dir.mkdir()
    for name, source in tools.items():
        write_tool(tool_dir / name, source)

    environment = os.environ.copy()
    environment.update(
        {
            "PATH": f"{tool_dir}{os.pathsep}{environment['PATH']}",
            "SOURCE_DATE_EPOCH": "0",
            "SSHFLING_VERSION": VERSION,
            "TMPDIR": str(repo / "tmp"),
        }
    )
    (repo / "tmp").mkdir()
    if blank_output:
        environment["FAKE_BLANK_OUTPUT"] = "1"

    return subprocess.run(
        [
            "bash",
            str(repo / "packaging" / "build-systems-languages.sh"),
            "--allow-blocked",
            "--language",
            language,
        ],
        cwd=repo,
        env=environment,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


class SystemsLanguageEvidenceTests(unittest.TestCase):
    def test_only_archive_lifecycle_builders_declare_lifecycle_capabilities(self) -> None:
        source = SCRIPT.read_text(encoding="utf-8")
        modes = parse_array(source, "validation_modes")
        capabilities = parse_array(source, "validation_capabilities")
        registry = {
            line.split("|", 1)[0]
            for line in (REPO_ROOT / "packaging" / "systems-languages" / "packages.tsv")
            .read_text(encoding="utf-8")
            .splitlines()
            if line and not line.startswith("#")
        }

        self.assertEqual(set(modes), registry)
        self.assertEqual(set(capabilities), registry)
        self.assertEqual(
            {slug for slug, mode in modes.items() if mode == "archive-lifecycle"},
            LIFECYCLE_LANGUAGES,
        )
        for slug in registry:
            declared = set(capabilities[slug].split(","))
            if slug in LIFECYCLE_LANGUAGES:
                self.assertTrue(LIFECYCLE_CAPABILITIES <= declared, slug)
            else:
                self.assertTrue(LIFECYCLE_CAPABILITIES.isdisjoint(declared), slug)

    def test_build_only_evidence_omits_lifecycle_claims(self) -> None:
        with validator_fixture() as repo:
            completed = run_validator(
                repo,
                "fortran",
                {"gcc": FAKE_COMPILER, "gfortran": FAKE_COMPILER},
            )
            rows = read_evidence(repo)

        self.assertEqual(completed.returncode, 0, completed.stderr)
        runtime = next(
            row for row in rows if row["subject"] == "fortran" and row["phase"] == "runtime-validation"
        )
        fields = detail_fields(runtime)
        self.assertEqual(runtime["status"], "PASS")
        self.assertEqual(fields["mode"], "build-only")
        self.assertEqual(
            set(fields["capabilities"].split(",")),
            {"compile", "cli-runtime", "init-workflow", "exit-workflow"},
        )
        self.assertTrue(
            LIFECYCLE_CAPABILITIES.isdisjoint(fields["capabilities"].split(","))
        )
        self.assertFalse(
            {"install", "isolated-consumer", "uninstall", "uninstall-import"}
            & {row["phase"] for row in rows if row["subject"] == "fortran"}
        )
        self.assertEqual(
            {
                row["phase"]
                for row in rows
                if row["subject"] == "fortran"
                and row["phase"]
                in {"cli-version", "init-template", "invalid-option", "missing-runtime"}
            },
            {"cli-version", "init-template", "invalid-option", "missing-runtime"},
        )
        self.assertFalse(any(row["subject"] == "native" for row in rows))
        self.assertIn("RUNTIME\tfortran\tPASS\t", completed.stdout)

    def test_archive_lifecycle_evidence_records_each_lifecycle_phase(self) -> None:
        with validator_fixture() as repo:
            completed = run_validator(
                repo,
                "odin",
                {"gcc": FAKE_COMPILER, "odin": FAKE_ODIN},
            )
            rows = read_evidence(repo)

        self.assertEqual(completed.returncode, 0, completed.stderr)
        runtime = next(
            row for row in rows if row["subject"] == "odin" and row["phase"] == "runtime-validation"
        )
        fields = detail_fields(runtime)
        self.assertEqual(runtime["status"], "PASS")
        self.assertEqual(fields["mode"], "archive-lifecycle")
        self.assertTrue(
            LIFECYCLE_CAPABILITIES <= set(fields["capabilities"].split(","))
        )
        lifecycle_statuses = {
            row["phase"]: row["status"]
            for row in rows
            if row["subject"] == "odin"
            and row["phase"]
            in {"install", "isolated-consumer", "uninstall", "uninstall-import"}
        }
        self.assertEqual(
            lifecycle_statuses,
            {
                "install": "PASS",
                "isolated-consumer": "PASS",
                "uninstall": "PASS",
                "uninstall-import": "PASS",
            },
        )

    def test_failed_builder_assertion_cannot_record_runtime_pass(self) -> None:
        with validator_fixture() as repo:
            completed = run_validator(
                repo,
                "odin",
                {"gcc": FAKE_COMPILER, "odin": FAKE_ODIN},
                blank_output=True,
            )
            rows = read_evidence(repo)

        runtime_rows = [
            row
            for row in rows
            if row["subject"] == "odin" and row["phase"] == "runtime-validation"
        ]
        self.assertEqual(completed.returncode, 1)
        self.assertEqual([row["status"] for row in runtime_rows], ["FAIL"])
        self.assertNotEqual(detail_fields(runtime_rows[0])["builder_exit"], "0")
        self.assertFalse(
            any(
                row["subject"] == "odin"
                and row["phase"] == "isolated-consumer"
                and row["status"] == "PASS"
                for row in rows
            )
        )
        self.assertIn("RUNTIME\todin\tFAIL\tbuilder_exit=", completed.stdout)


if __name__ == "__main__":
    unittest.main()
