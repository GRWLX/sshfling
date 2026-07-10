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

    def write_scripting(
        self,
        path: Path,
        blocked: tuple[str, str] | None = None,
        missing: tuple[str, str] | None = None,
        wrong_version: tuple[str, str] | None = None,
    ) -> None:
        with path.open("w", encoding="utf-8", newline="") as stream:
            writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
            writer.writerow(["RESULT", "batch", "source-version", "PASS", "0.1.16"])
            for language in validator.SCRIPTING_LANGUAGES:
                for phase in validator.SCRIPTING_LIFECYCLE_PHASES:
                    if missing == (language, phase):
                        continue
                    status = "SKIP" if blocked == (language, phase) else "PASS"
                    version = "9.9.9" if wrong_version == (language, phase) else "0.1.16"
                    detail = "checked=yes"
                    if phase == "package-archive":
                        detail = (
                            f"artifact=sshfling-{language}-{version}.tar.gz;"
                            f"sha256={'c' * 64};repeat_build=identical;source_date_epoch=0"
                        )
                    elif phase in {"package-cli-version", "symlink-cli-version"}:
                        detail = f"sshfling {version}"
                    elif phase == "guile-runtime":
                        detail = f"sshfling {version}; init-assets=24"
                    elif phase == "guix-definition":
                        detail = "guix-dry-run"
                    elif phase == "removal":
                        detail = f"isolated-prefix-absent=/tmp/sshfling-{language}-{version}"
                    elif phase == "removal-source":
                        detail = "guile-module-and-guix-definition-absent"
                    writer.writerow(["RESULT", language, phase, status, detail])

    def write_systems(
        self,
        path: Path,
        blocked: tuple[str, str] | None = None,
        missing: tuple[str, str] | None = None,
        incomplete_capabilities: str | None = None,
        contradictory_zig: bool = False,
    ) -> None:
        with path.open("w", encoding="utf-8", newline="") as stream:
            writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
            writer.writerow(["record", "subject", "phase", "status", "detail"])
            writer.writerow(["RESULT", "batch", "source-version", "PASS", "version=0.1.16"])
            for language in validator.SYSTEM_LANGUAGES:
                for phase in validator.SYSTEM_LIFECYCLE_PHASES:
                    if missing == (language, phase):
                        continue
                    status = "BLOCKED" if blocked == (language, phase) else "PASS"
                    detail = "checked=yes"
                    if phase == "source-archive":
                        detail = (
                            f"artifact=sshfling-{language}-0.1.16.tar.gz;"
                            f"sha256={'a' * 64};files=39;inventory_sha256={'b' * 64};"
                            "repeat_build=identical"
                        )
                    elif phase == "install":
                        detail = "isolated_prefix=/tmp/install;source_archive_extracted=yes"
                    elif phase in {"isolated-consumer", "cli-version"}:
                        detail = "output=sshfling 0.1.16"
                        if language == "swift" and phase == "isolated-consumer":
                            detail = (
                                "swiftpm_local_dependency=yes;package_version=0.1.16;"
                                "runtime_version=0.1.16;output=sshfling 0.1.16"
                            )
                    elif phase == "runtime-validation":
                        capabilities = validator.SYSTEM_LIFECYCLE_CAPABILITIES[language]
                        if incomplete_capabilities == language:
                            capabilities = capabilities[:-1]
                        detail = (
                            "builder_exit=0;mode=archive-lifecycle;capabilities="
                            + ",".join(capabilities)
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
            scripting = root / "scripting.tsv"
            self.write_functional(functional)
            self.write_systems(systems)
            self.write_scripting(scripting)
            self.assertEqual(validator.validate(functional, systems, scripting, "0.1.16"), [])

    def test_rejects_blocked_functional_outcome(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            functional = root / "functional.tsv"
            systems = root / "systems.tsv"
            scripting = root / "scripting.tsv"
            self.write_functional(functional, blocked="julia")
            self.write_systems(systems)
            self.write_scripting(scripting)
            self.assertTrue(
                any("julia" in error for error in validator.validate(functional, systems, scripting, "0.1.16"))
            )

    def test_rejects_missing_system_lifecycle_phase(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            functional = root / "functional.tsv"
            systems = root / "systems.tsv"
            scripting = root / "scripting.tsv"
            self.write_functional(functional)
            self.write_systems(systems, blocked=("v", "uninstall"))
            self.write_scripting(scripting)
            errors = validator.validate(functional, systems, scripting, "0.1.16")
            self.assertTrue(any("v: uninstall is not PASS" == error for error in errors))

    def test_rejects_missing_swift_lifecycle_phase(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            functional = root / "functional.tsv"
            systems = root / "systems.tsv"
            scripting = root / "scripting.tsv"
            self.write_functional(functional)
            self.write_systems(systems, missing=("swift", "uninstall-import"))
            self.write_scripting(scripting)
            errors = validator.validate(functional, systems, scripting, "0.1.16")
            self.assertIn("swift: uninstall-import is not PASS", errors)

    def test_rejects_blocked_swift_lifecycle_phase(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            functional = root / "functional.tsv"
            systems = root / "systems.tsv"
            scripting = root / "scripting.tsv"
            self.write_functional(functional)
            self.write_systems(systems, blocked=("swift", "isolated-consumer"))
            self.write_scripting(scripting)
            errors = validator.validate(functional, systems, scripting, "0.1.16")
            self.assertIn("swift: isolated-consumer is not PASS", errors)
            self.assertIn("swift: contradictory systems failure evidence", errors)

    def test_rejects_incomplete_swift_runtime_capabilities(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            functional = root / "functional.tsv"
            systems = root / "systems.tsv"
            scripting = root / "scripting.tsv"
            self.write_functional(functional)
            self.write_systems(systems, incomplete_capabilities="swift")
            self.write_scripting(scripting)
            errors = validator.validate(functional, systems, scripting, "0.1.16")
            self.assertIn("swift: runtime capability evidence is incomplete", errors)

    def test_rejects_evidence_for_a_different_version(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            functional = root / "functional.tsv"
            systems = root / "systems.tsv"
            scripting = root / "scripting.tsv"
            self.write_functional(functional)
            self.write_systems(systems)
            self.write_scripting(scripting)
            errors = validator.validate(functional, systems, scripting, "9.9.9")
            self.assertTrue(any("version" in error or "output" in error for error in errors))

    def test_rejects_mismatched_functional_actual_output(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            functional = root / "functional.tsv"
            systems = root / "systems.tsv"
            scripting = root / "scripting.tsv"
            self.write_functional(functional, wrong_output="julia")
            self.write_systems(systems)
            self.write_scripting(scripting)
            errors = validator.validate(functional, systems, scripting, "0.1.16")
            self.assertIn("julia: lacks exact version 0.1.16 output evidence", errors)

    def test_rejects_contradictory_zig_phase_rows(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            functional = root / "functional.tsv"
            systems = root / "systems.tsv"
            scripting = root / "scripting.tsv"
            self.write_functional(functional)
            self.write_systems(systems, contradictory_zig=True)
            self.write_scripting(scripting)
            errors = validator.validate(functional, systems, scripting, "0.1.16")
            self.assertIn("zig: cli-version is not PASS", errors)
            self.assertIn("zig: contradictory systems failure evidence", errors)

    def test_rejects_missing_guix_definition_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            functional = root / "functional.tsv"
            systems = root / "systems.tsv"
            scripting = root / "scripting.tsv"
            self.write_functional(functional)
            self.write_systems(systems)
            self.write_scripting(scripting, missing=("guix-scheme", "guix-definition"))
            errors = validator.validate(functional, systems, scripting, "0.1.16")
            self.assertIn("guix-scheme: guix-definition is not PASS", errors)
            self.assertIn(
                "guix-scheme: guix package-definition evidence is not dry-run",
                errors,
            )

    def test_rejects_skipped_guix_definition_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            functional = root / "functional.tsv"
            systems = root / "systems.tsv"
            scripting = root / "scripting.tsv"
            self.write_functional(functional)
            self.write_systems(systems)
            self.write_scripting(scripting, blocked=("guix-scheme", "guix-definition"))
            errors = validator.validate(functional, systems, scripting, "0.1.16")
            self.assertIn("guix-scheme: guix-definition is not PASS", errors)
            self.assertIn("guix-scheme: contradictory scripting failure evidence", errors)

    def test_release_workflows_depend_on_strict_catalog_evidence(self) -> None:
        makefile = (REPO_ROOT / "Makefile").read_text(encoding="utf-8")
        self.assertIn("package-language-catalog-strict:", makefile)
        self.assertIn("validate_promoted_language_evidence.py", makefile)
        self.assertIn('--version "$(VERSION)"', makefile)
        self.assertIn("--scripting", makefile)

        runtime_workflow = (
            REPO_ROOT / ".github/workflows/language-runtime-validation.yml"
        ).read_text(encoding="utf-8")
        self.assertIn("tools/provision-promoted-language-runtimes.sh", runtime_workflow)
        self.assertIn("make package-language-catalog-strict", runtime_workflow)
        self.assertIn("name: language-catalog-packages", runtime_workflow)
        self.assertIn("guix-daemon", runtime_workflow)
        self.assertIn("guix liblua5.1", runtime_workflow)

        provisioner = (REPO_ROOT / "tools/provision-promoted-language-runtimes.sh").read_text(
            encoding="utf-8"
        )
        self.assertIn("907daf191ad3f1cf7e5190ec4f44eb29cd54ba21", provisioner)
        self.assertIn("11c4df319b18ed26946962883e7646e3d510c63b19dafb064a5060b792e549e0", provisioner)
        self.assertIn("f88d95236319460327b05efcfdab7c342caa7d22", provisioner)
        self.assertIn("95c75a49f8b3d15b8ae1ddf10f9589bc0fd0eecf84d432bad163191f900cb23c", provisioner)
        self.assertIn("96e8be05e6f7176433ada74532ff36a62b8dc44c5247a82cdf919f2dadc5178b", provisioner)
        self.assertIn("b39305547cb05754aecd94adf683e92f907cbb9259fd667e851651d69d558f35", provisioner)
        self.assertIn("24a86c61b9de359001729bf83600bb91eba1443dd114bd1eb8ba88167a641db4", provisioner)
        self.assertIn("eb09ce5761a8c989f1993d451200527a3ebf0f253543e1aaf8fbe53b6a9bdb7b", provisioner)
        self.assertIn("janet jpm zig", provisioner)
        self.assertIn("hbmk2 ring red roc gst gst-package apl bal", provisioner)

        for relative in (
            ".github/workflows/release-packages.yml",
            ".github/workflows/public-package-web.yml",
        ):
            workflow = (REPO_ROOT / relative).read_text(encoding="utf-8")
            self.assertIn("uses: ./.github/workflows/language-runtime-validation.yml", workflow)
            self.assertIn("validate_promoted_language_evidence.py", workflow)
            self.assertIn('--version "$version"', workflow)
            self.assertIn("--scripting", workflow)


if __name__ == "__main__":
    unittest.main()
