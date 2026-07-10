from __future__ import annotations

import csv
import importlib.util
from pathlib import Path
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "validate_promoted_language_evidence",
    REPO_ROOT / "tools" / "validate_promoted_language_evidence.py",
)
assert SPEC and SPEC.loader
validator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(validator)


class PromotedLanguageEvidenceTests(unittest.TestCase):
    def write_functional(
        self,
        path: Path,
        blocked: str | None = None,
        wrong_output: str | None = None,
    ) -> None:
        fields = [
            "timestamp_utc", "language", "result", "phase", "status", "cwd",
            "command", "stdout", "stderr", "detail",
        ]
        with path.open("w", encoding="utf-8", newline="") as stream:
            writer = csv.DictWriter(stream, fieldnames=fields, delimiter="\t", lineterminator="\n")
            writer.writeheader()
            writer.writerow(
                {
                    "language": "validator",
                    "result": "PASS",
                    "phase": "canonical-runtime",
                    "status": "0",
                    "detail": "version=0.1.16;files=25;requested=0.1.16",
                }
            )
            for language in validator.FUNCTIONAL_LANGUAGES:
                writer.writerow(
                    {
                        "language": language,
                        "result": "PASS",
                        "phase": "canonical-bundle",
                        "status": "0",
                        "detail": "bundle=runtime;files=25;version=0.1.16",
                    }
                )
                writer.writerow(
                    {
                        "language": language,
                        "result": "PASS",
                        "phase": "exact-version-output",
                        "status": "0",
                        "detail": (
                            "expected=sshfling 0.1.16;"
                            f"actual=sshfling {'9.9.9' if language == wrong_output else '0.1.16'}"
                        ),
                    }
                )
                writer.writerow(
                    {
                        "language": language,
                        "result": "BLOCKED" if language == blocked else "PASS",
                        "phase": "outcome",
                        "status": "0",
                        "detail": "archive=yes;install=yes;consumer=yes;remove=yes",
                    }
                )

    def write_systems(
        self,
        path: Path,
        blocked: tuple[str, str] | None = None,
        contradictory_zig: bool = False,
    ) -> None:
        with path.open("w", encoding="utf-8", newline="") as stream:
            writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
            writer.writerow(["record", "subject", "phase", "status", "detail"])
            writer.writerow(["RESULT", "batch", "source-version", "PASS", "version=0.1.16"])
            for language in validator.SYSTEM_LANGUAGES:
                for phase in validator.SYSTEM_LIFECYCLE_PHASES:
                    status = "BLOCKED" if blocked == (language, phase) else "PASS"
                    detail = (
                        "output=sshfling 0.1.16"
                        if phase in {"isolated-consumer", "cli-version"}
                        else "checked=yes"
                    )
                    writer.writerow(["RESULT", language, phase, status, detail])
            for language in validator.SYSTEM_BUILD_LANGUAGES:
                for phase in (
                    "source-archive",
                    "cli-version",
                    "init-template",
                    "invalid-option",
                    "missing-runtime",
                    "runtime-validation",
                ):
                    detail = "checked=yes"
                    if phase == "cli-version":
                        detail = "output=sshfling 0.1.16"
                    elif phase == "runtime-validation":
                        detail = "builder_exit=0;mode=build-only;capabilities=compile"
                    writer.writerow(["RESULT", language, phase, "PASS", detail])
            if contradictory_zig:
                writer.writerow(["RESULT", "zig", "cli-version", "FAIL", "output=sshfling 9.9.9"])

    def test_accepts_complete_pass_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            functional = root / "functional.tsv"
            systems = root / "systems.tsv"
            self.write_functional(functional)
            self.write_systems(systems)
            self.assertEqual(validator.validate(functional, systems, "0.1.16"), [])

    def test_rejects_blocked_functional_outcome(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            functional = root / "functional.tsv"
            systems = root / "systems.tsv"
            self.write_functional(functional, blocked="julia")
            self.write_systems(systems)
            self.assertTrue(
                any("julia" in error for error in validator.validate(functional, systems, "0.1.16"))
            )

    def test_rejects_missing_system_lifecycle_phase(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            functional = root / "functional.tsv"
            systems = root / "systems.tsv"
            self.write_functional(functional)
            self.write_systems(systems, blocked=("v", "uninstall"))
            errors = validator.validate(functional, systems, "0.1.16")
            self.assertTrue(any("v: uninstall is not PASS" == error for error in errors))

    def test_rejects_evidence_for_a_different_version(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            functional = root / "functional.tsv"
            systems = root / "systems.tsv"
            self.write_functional(functional)
            self.write_systems(systems)
            errors = validator.validate(functional, systems, "9.9.9")
            self.assertTrue(any("version" in error or "output" in error for error in errors))

    def test_rejects_mismatched_functional_actual_output(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            functional = root / "functional.tsv"
            systems = root / "systems.tsv"
            self.write_functional(functional, wrong_output="julia")
            self.write_systems(systems)
            errors = validator.validate(functional, systems, "0.1.16")
            self.assertIn("julia: lacks exact version 0.1.16 output evidence", errors)

    def test_rejects_contradictory_zig_phase_rows(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            functional = root / "functional.tsv"
            systems = root / "systems.tsv"
            self.write_functional(functional)
            self.write_systems(systems, contradictory_zig=True)
            errors = validator.validate(functional, systems, "0.1.16")
            self.assertIn("zig: cli-version is not PASS", errors)
            self.assertIn("zig: contradictory systems failure evidence", errors)

    def test_release_workflows_depend_on_strict_catalog_evidence(self) -> None:
        makefile = (REPO_ROOT / "Makefile").read_text(encoding="utf-8")
        self.assertIn("package-language-catalog-strict:", makefile)
        self.assertIn("validate_promoted_language_evidence.py", makefile)
        self.assertIn('--version "$(VERSION)"', makefile)

        runtime_workflow = (
            REPO_ROOT / ".github/workflows/language-runtime-validation.yml"
        ).read_text(encoding="utf-8")
        self.assertIn("tools/provision-promoted-language-runtimes.sh", runtime_workflow)
        self.assertIn("make package-language-catalog-strict", runtime_workflow)
        self.assertIn("name: language-catalog-packages", runtime_workflow)

        provisioner = (REPO_ROOT / "tools/provision-promoted-language-runtimes.sh").read_text(
            encoding="utf-8"
        )
        self.assertIn("907daf191ad3f1cf7e5190ec4f44eb29cd54ba21", provisioner)
        self.assertIn("11c4df319b18ed26946962883e7646e3d510c63b19dafb064a5060b792e549e0", provisioner)
        self.assertIn("janet jpm zig", provisioner)

        for relative in (
            ".github/workflows/release-packages.yml",
            ".github/workflows/public-package-web.yml",
        ):
            workflow = (REPO_ROOT / relative).read_text(encoding="utf-8")
            self.assertIn("uses: ./.github/workflows/language-runtime-validation.yml", workflow)
            self.assertIn("validate_promoted_language_evidence.py", workflow)
            self.assertIn('--version "$version"', workflow)


if __name__ == "__main__":
    unittest.main()
