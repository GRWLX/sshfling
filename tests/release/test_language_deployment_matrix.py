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
    def test_matrix_has_at_least_400_verified_cells(self) -> None:
        cells = matrix.verification_cells()

        self.assertGreaterEqual(len(cells), 400)
        self.assertEqual({cell["status"] for cell in cells}, {"PASS"})
        self.assertEqual(len({cell["cell_id"] for cell in cells}), len(cells))

    def test_matrix_validation_accepts_current_surfaces(self) -> None:
        self.assertEqual(matrix.validate_matrix(), [])

    def test_new_deployments_append_without_renumbering_existing_cells(self) -> None:
        ids = [str(item["id"]) for item in matrix.DEPLOYMENTS]

        self.assertEqual(ids[73], "julia-pkg-library")
        self.assertEqual(ids[80], "dart-native-cli-consumer")
        self.assertEqual(ids[81], "swift-swiftpm-library")

    def test_first_91_catalog_has_complete_explicit_coverage(self) -> None:
        cells = matrix.catalog_cells()
        expected = list(matrix.FIRST_91_CATALOG)
        by_order: dict[int, list[dict[str, str]]] = {}
        for cell in cells:
            by_order.setdefault(int(cell["order"]), []).append(cell)

        self.assertEqual(len(expected), 91)
        self.assertEqual(len({language for language, _status in expected}), 91)
        self.assertEqual(set(by_order), set(range(1, 92)))
        todo = matrix.todo_first_91_catalog()
        self.assertEqual(
            [language for language, _status in todo],
            [language for language, _status in expected],
        )
        self.assertEqual(len({cell["cell_id"] for cell in cells}), len(cells))
        self.assertEqual(len({cell["surface_id"] for cell in cells}), len(cells))
        for order, (language, expected_status) in enumerate(expected, start=1):
            language_cells = by_order[order]
            self.assertEqual({cell["language"] for cell in language_cells}, {language})
            self.assertEqual(
                matrix.derived_catalog_status(language_cells),
                expected_status,
                language,
            )
            for cell in language_cells:
                for field in (
                    "package_manager",
                    "deployment_type",
                    "interface_type",
                    "artifact",
                    "evidence",
                ):
                    self.assertTrue(cell[field].strip(), f"{cell['surface_id']}:{field}")

    def test_pass_status_rejects_skip_blocked_or_failed_evidence(self) -> None:
        skip = dict(matrix.DEPLOYMENTS[0])
        skip["validation_evidence"] = "RESULT runtime SKIP tool-not-found"
        blocked = dict(matrix.DEPLOYMENTS[0])
        blocked["validation_status"] = "BLOCKED"
        blocked["validation_evidence"] = "BLOCKED runtime-validation"

        skip_errors = matrix.status_evidence_errors([skip], "fixture")
        blocked_errors = matrix.status_evidence_errors([blocked], "fixture")
        self.assertTrue(any("PASS evidence contains" in error for error in skip_errors))
        self.assertTrue(any("disagrees" in error for error in blocked_errors))
        self.assertTrue(any("PASS evidence contains" in error for error in blocked_errors))

    def test_source_publication_pass_is_separate_from_blocked_runtime(self) -> None:
        by_language: dict[str, list[dict[str, str]]] = {}
        for cell in matrix.catalog_cells():
            by_language.setdefault(cell["language"], []).append(cell)

        for language in (
            "Smalltalk",
            "APL",
            "Q/KDB+",
        ):
            cells = by_language[language]
            publications = [
                cell
                for cell in cells
                if cell["deployment_type"] == "versioned source-archive publication"
            ]
            runtimes = [cell for cell in cells if cell["status"] == "BLOCKED"]
            self.assertEqual(len(publications), 1, language)
            self.assertEqual(publications[0]["status"], "PASS", language)
            self.assertEqual(publications[0]["interface_type"], "source package", language)
            self.assertNotRegex(
                publications[0]["evidence"],
                matrix.CONTRADICTORY_PASS_EVIDENCE,
                language,
            )
            self.assertEqual(len(runtimes), 1, language)
            self.assertEqual(matrix.derived_catalog_status(cells), "BLOCKED", language)

    def test_new_runtime_passes_are_synchronized_with_todo_status(self) -> None:
        by_language: dict[str, list[dict[str, str]]] = {}
        for cell in matrix.catalog_cells():
            by_language.setdefault(cell["language"], []).append(cell)

        for language in (
            "Swift",
            "Dart",
            "Julia",
            "V",
            "J",
            "Guix Scheme",
            "WebAssembly/WASI",
            "Pony",
            "Janet",
            "Odin",
            "CFML",
            "Chapel",
            "Ballerina",
            "Roc",
        ):
            cells = by_language[language]
            self.assertEqual(matrix.derived_catalog_status(cells), "PASS", language)
            self.assertTrue(
                any(
                    cell["status"] == "PASS"
                    and "source-archive publication" not in cell["deployment_type"]
                    for cell in cells
                ),
                language,
            )
            self.assertEqual({cell["catalog_status"] for cell in cells}, {"PASS"})
            self.assertEqual({cell["todo_status"] for cell in cells}, {"PASS"})

    def test_each_pass_catalog_language_has_library_or_cli_runtime(self) -> None:
        by_language: dict[str, list[dict[str, str]]] = {}
        for cell in matrix.catalog_cells():
            by_language.setdefault(cell["language"], []).append(cell)

        for language, status in matrix.FIRST_91_CATALOG:
            if status != "PASS":
                continue
            self.assertTrue(
                any(
                    cell["status"] == "PASS"
                    and any(
                        token in cell["interface_type"].lower()
                        for token in ("library", "cli", "command", "module")
                    )
                    for cell in by_language[language]
                ),
                language,
            )
        self.assertNotIn("NOT_APPLICABLE", matrix.render_library_index())

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
        self.assertGreaterEqual(len(library_surfaces), 50)
        for language in (
            "C#/.NET",
            "Java",
            "C",
            "C++",
            "Visual Basic/.NET",
            "F#",
            "Perl",
            "Kotlin",
            "Scala",
            "Groovy",
            "Clojure",
            "Elm",
            "PureScript",
            "Reason/ReScript",
            "React/JSX",
            "Vue",
            "Svelte",
            "Angular",
            "HTML/CSS",
            "Tcl",
            "AWK",
            "Lua",
            "PowerShell",
            "Ring",
        ):
            self.assertTrue(
                any(item["language"] == language for item in library_surfaces),
                language,
            )

    def test_jvm_language_consumers_use_the_java_package(self) -> None:
        deployments = {item["id"]: item for item in matrix.DEPLOYMENTS}
        build_script = (REPO_ROOT / "packaging/build-java.sh").read_text(encoding="utf-8")
        published_workflow = (
            REPO_ROOT / ".github/workflows/package-install-tests.yml"
        ).read_text(encoding="utf-8")

        for language in ("Java", "Kotlin", "Scala", "Groovy", "Clojure"):
            managers = {
                item["package_manager"]
                for item in matrix.DEPLOYMENTS
                if item["language"] == language
            }
            self.assertTrue({"Maven", "Gradle"}.issubset(managers), language)

        for language in ("kotlin", "scala", "groovy"):
            maven_item = deployments[f"{language}-maven-library"]
            gradle_item = deployments[f"{language}-gradle-library"]
            self.assertEqual(maven_item["package_manager"], "Maven")
            self.assertEqual(gradle_item["package_manager"], "Gradle")
            self.assertEqual(maven_item["build_target"], "package-java")
            self.assertEqual(gradle_item["build_target"], "package-java")
            self.assertIn(f"    {language} \\\n", build_script)
            self.assertIn(f"consumers/$language", published_workflow)
            self.assertIn(f"consumers/$language-gradle", published_workflow)

        for deployment_id in ("clojure-maven-library", "clojure-gradle-library"):
            self.assertEqual(deployments[deployment_id]["build_target"], "package-java")
        self.assertIn("validate_clojure_maven_consumer", build_script)
        self.assertIn("validate_clojure_gradle_consumer", build_script)
        self.assertIn("consumers/clojure", published_workflow)
        self.assertIn("consumers/clojure-gradle", published_workflow)

    def test_web_language_consumers_use_the_packed_node_library(self) -> None:
        deployments = {item["id"]: item for item in matrix.DEPLOYMENTS}
        makefile = (REPO_ROOT / "Makefile").read_text(encoding="utf-8")
        workflow = (REPO_ROOT / ".github/workflows/package-install-tests.yml").read_text(
            encoding="utf-8"
        )

        for consumer in (
            "react",
            "vue",
            "svelte",
            "angular",
            "elm",
            "purescript",
            "rescript",
            "html-css",
            "cfml",
        ):
            item = deployments[f"{consumer}-npm-consumer"]
            self.assertEqual(item["build_target"], "package-web-language-consumers")
            self.assertIn(f"packaging/node/consumers/{consumer}", str(item["required_paths"]))
            self.assertIn(consumer, workflow)
        dart = deployments["dart-native-cli-consumer"]
        self.assertEqual(dart["build_target"], "package-web-language-consumers")
        self.assertEqual(dart["interface_type"], "native CLI consumer")
        self.assertIn("dart compile exe", dart["evidence"]["build"])
        self.assertIn("dart format", dart["evidence"]["build"])
        self.assertIn("dart analyze", dart["evidence"]["build"])
        self.assertIn("packaging/node/consumers/dart", str(dart["required_paths"]))
        self.assertIn("dart", workflow)
        self.assertIn("package-web-language-consumers:", makefile)

    def test_scripting_language_packages_use_the_batch_validator(self) -> None:
        deployments = {item["id"]: item for item in matrix.DEPLOYMENTS}
        makefile = (REPO_ROOT / "Makefile").read_text(encoding="utf-8")
        build_script = (REPO_ROOT / "packaging/build-scripting-languages.sh").read_text(
            encoding="utf-8"
        )

        for deployment_id in (
            "tcl-package-library",
            "awk-source-library",
            "sed-command-package",
            "lua-source-library",
            "lua-luarocks-library",
            "zsh-source-module",
            "fish-source-module",
            "elvish-source-module",
            "nushell-source-module",
            "powershell-module-package",
            "guix-scheme-guile-library",
            "guix-scheme-guix-package",
        ):
            self.assertEqual(
                deployments[deployment_id]["build_target"],
                "package-scripting-languages",
            )
        self.assertEqual(
            deployments["guix-scheme-guix-package"]["package_manager"],
            "Guix",
        )
        self.assertIn(
            "guix-definition PASS",
            deployments["guix-scheme-guix-package"]["validation_evidence"],
        )
        for builder in ("build_tcl", "build_awk", "build_sed", "build_lua"):
            self.assertIn(builder, build_script)
        for language in ("zsh", "fish"):
            self.assertIn(f'  "{language}" "{language}"', build_script)
        self.assertIn("package-scripting-languages:", makefile)

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
        libraries_path = REPO_ROOT / "docs/libraries.md"

        self.assertTrue(path.is_file())
        self.assertEqual(path.read_text(encoding="utf-8"), matrix.render_markdown())
        libraries = libraries_path.read_text(encoding="utf-8")
        self.assertIn(matrix.LIBRARIES_BEGIN, libraries)
        self.assertIn(matrix.LIBRARIES_END, libraries)
        self.assertEqual(
            libraries,
            matrix.replace_between(
                libraries,
                matrix.LIBRARIES_BEGIN,
                matrix.LIBRARIES_END,
                matrix.render_library_index(),
            ),
        )

    def test_each_surface_has_all_eight_check_types(self) -> None:
        expected = {check_id for check_id, _name in matrix.CHECKS}

        for item in matrix.DEPLOYMENTS:
            self.assertEqual(set(item["evidence"]), expected, item["id"])


if __name__ == "__main__":
    unittest.main()
