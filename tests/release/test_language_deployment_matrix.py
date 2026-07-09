from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
GENERATOR_PATH = REPO_ROOT / "tools/generate_language_deployment_matrix.py"


def load_generator():
    spec = importlib.util.spec_from_file_location("generate_language_deployment_matrix", GENERATOR_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


matrix = load_generator()


class LanguageDeploymentMatrixTests(unittest.TestCase):
    def test_matrix_has_at_least_192_verified_cells(self) -> None:
        cells = matrix.verification_cells()

        self.assertGreaterEqual(len(cells), 192)
        self.assertEqual({cell["status"] for cell in cells}, {"PASS"})
        self.assertEqual(len({cell["cell_id"] for cell in cells}), len(cells))

    def test_matrix_validation_accepts_current_surfaces(self) -> None:
        self.assertEqual(matrix.validate_matrix(), [])

    def test_package_managers_and_library_surfaces_are_explicit(self) -> None:
        managers = {item["package_manager"] for item in matrix.DEPLOYMENTS}
        library_surfaces = [
            item for item in matrix.DEPLOYMENTS if "library" in item["interface_type"]
        ]

        self.assertIn("Maven", managers)
        self.assertIn("Gradle", managers)
        self.assertIn("CMake", managers)
        self.assertIn("pkg-config", managers)
        self.assertIn("MakeMaker/CPAN", managers)
        self.assertGreaterEqual(len(library_surfaces), 19)
        for language in (
            "C#/.NET",
            "Java",
            "C",
            "C++",
            "Visual Basic/.NET",
            "F#",
            "Perl",
        ):
            self.assertTrue(
                any(item["language"] == language for item in library_surfaces),
                language,
            )

    def test_native_linkage_types_are_separate_consumers(self) -> None:
        deployments = {item["id"]: item for item in matrix.DEPLOYMENTS}

        self.assertEqual(
            deployments["c-cmake-shared"]["deployment_type"],
            "shared-library dependency",
        )
        self.assertEqual(
            deployments["c-cmake-static"]["deployment_type"],
            "static-library dependency",
        )
        self.assertEqual(deployments["c-pkg-config"]["package_manager"], "pkg-config")

    def test_native_and_perl_artifacts_are_release_integrated(self) -> None:
        integration_paths = (
            ".github/workflows/release-packages.yml",
            ".github/workflows/public-package-web.yml",
            ".github/workflows/package-install-tests.yml",
            "packaging/build-public-web.sh",
            "packaging/verify-public-web.sh",
            "tests/release/validate-package-publishing-rehearsal.sh",
            "tests/release/validate-release-matrix.sh",
            "tools/generate_release_evidence.py",
        )
        for relative in integration_paths:
            content = (REPO_ROOT / relative).read_text(encoding="utf-8")
            self.assertIn("sshfling-native-", content, relative)
            self.assertIn("sshfling-perl-", content, relative)

        makefile = (REPO_ROOT / "Makefile").read_text(encoding="utf-8")
        package_dependencies = next(
            line for line in makefile.splitlines() if line.startswith("package:")
        )
        self.assertIn("package-native-libraries", package_dependencies)
        self.assertIn("package-perl", package_dependencies)

    def test_generated_document_is_current(self) -> None:
        path = REPO_ROOT / "docs/language-deployment-support.md"

        self.assertTrue(path.is_file())
        self.assertEqual(path.read_text(encoding="utf-8"), matrix.render_markdown())

    def test_each_surface_has_all_eight_check_types(self) -> None:
        expected = {check_id for check_id, _name in matrix.CHECKS}

        for item in matrix.DEPLOYMENTS:
            self.assertEqual(set(item["evidence"]), expected, item["id"])


if __name__ == "__main__":
    unittest.main()
