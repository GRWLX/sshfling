from __future__ import annotations

import csv
import importlib.util
import json
import re
import tomllib
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
GENERATOR_PATH = REPO_ROOT / "tools" / "generate_language_support_matrix.py"


def load_generator():
    if not GENERATOR_PATH.exists():
        return None

    spec = importlib.util.spec_from_file_location("generate_language_support_matrix", GENERATOR_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


generate_language_support_matrix = load_generator()


def language_name(row: dict) -> str:
    for key in ("language", "name"):
        value = row.get(key)
        if isinstance(value, str) and value:
            return value
    raise AssertionError(f"language support row is missing a language/name field: {row!r}")


def status_value(row: dict) -> str:
    value = row.get("status")
    if isinstance(value, str) and value:
        return value
    raise AssertionError(f"language support row is missing a status field: {row!r}")


def allowed_statuses(module) -> set[str]:
    statuses = getattr(module, "ALLOWED_STATUSES", None)
    if statuses is None:
        statuses = getattr(module, "STATUS_ORDER", None)
    if statuses is None:
        raise AssertionError("generator must expose ALLOWED_STATUSES or STATUS_ORDER")
    return {str(status) for status in statuses}


def evidence_value(row: dict):
    for key in ("evidence", "evidence_url", "evidence_urls", "evidence_path", "evidence_paths"):
        if key in row:
            return row[key]
    return None


def has_evidence(row: dict) -> bool:
    evidence = evidence_value(row)
    if isinstance(evidence, str):
        return bool(evidence.strip())
    if isinstance(evidence, (list, tuple, set)):
        return any(bool(str(item).strip()) for item in evidence)
    return bool(evidence)


def is_unsupported(row: dict) -> bool:
    if row.get("supported") is False:
        return True
    if row.get("shipped") is False:
        return True
    for key in ("support", "tier", "category"):
        value = row.get(key)
        if isinstance(value, str) and value.upper() in {"UNSUPPORTED", "NOT_SUPPORTED"}:
            return True
    return status_value(row).upper() in {"UNSUPPORTED", "NOT_SUPPORTED"}


@unittest.skipIf(
    generate_language_support_matrix is None,
    "tools/generate_language_support_matrix.py is not present yet",
)
class LanguageSupportMatrixTests(unittest.TestCase):
    def test_language_support_has_no_duplicate_languages(self) -> None:
        languages = [language_name(row) for row in generate_language_support_matrix.LANGUAGE_SUPPORT]

        duplicates = sorted({language for language in languages if languages.count(language) > 1})

        self.assertEqual(duplicates, [])

    def test_language_support_uses_allowed_statuses_only(self) -> None:
        allowed = allowed_statuses(generate_language_support_matrix)
        statuses = {status_value(row) for row in generate_language_support_matrix.LANGUAGE_SUPPORT}

        self.assertEqual(statuses - allowed, set())

    def test_validate_language_support_accepts_current_matrix(self) -> None:
        result = generate_language_support_matrix.validate_language_support()

        self.assertIn(result, (None, True, []))

    def test_pass_languages_have_evidence(self) -> None:
        missing_evidence = [
            language_name(row)
            for row in generate_language_support_matrix.LANGUAGE_SUPPORT
            if status_value(row).upper() == "PASS" and not has_evidence(row)
        ]

        self.assertEqual(missing_evidence, [])

    def test_priority_languages_are_ordered_for_release_docs(self) -> None:
        languages = [language_name(row) for row in generate_language_support_matrix.LANGUAGE_SUPPORT]

        self.assertGreater(len(languages), 0)
        self.assertEqual(languages[0], "Python")
        self.assertLess(languages.index("TypeScript"), languages.index("JavaScript"))
        self.assertLess(languages.index("TypeScript"), languages.index("Java"))

    def test_powershell_package_is_supported(self) -> None:
        rows_by_language = {
            language_name(row): row for row in generate_language_support_matrix.LANGUAGE_SUPPORT
        }

        self.assertEqual(status_value(rows_by_language["PowerShell"]).upper(), "PASS")

    def test_javascript_typescript_package_surface_is_supported(self) -> None:
        rows_by_language = {
            language_name(row): row for row in generate_language_support_matrix.LANGUAGE_SUPPORT
        }
        node_package = REPO_ROOT / "packaging" / "node" / "package.json"
        package_metadata = json.loads(node_package.read_text(encoding="utf-8"))

        self.assertEqual(status_value(rows_by_language["TypeScript"]).upper(), "PASS")
        self.assertEqual(status_value(rows_by_language["JavaScript"]).upper(), "PASS")
        self.assertEqual(package_metadata["name"], "sshfling")
        self.assertEqual(package_metadata["bin"]["sshfling"], "./bin/sshfling.js")
        self.assertEqual(package_metadata["types"], "./index.d.ts")
        self.assertIn(".", package_metadata["exports"])
        self.assertTrue((REPO_ROOT / "packaging" / "node" / "index.js").is_file())
        self.assertTrue((REPO_ROOT / "packaging" / "node" / "index.d.ts").is_file())
        self.assertTrue((REPO_ROOT / "packaging" / "node" / "bin" / "sshfling.js").is_file())
        self.assertIn("package-node", (REPO_ROOT / "Makefile").read_text(encoding="utf-8"))

    def test_python_go_rust_php_and_ruby_package_surfaces_are_supported(self) -> None:
        rows_by_language = {
            language_name(row): row for row in generate_language_support_matrix.LANGUAGE_SUPPORT
        }
        for language in ("Python", "Go", "Rust", "PHP", "Ruby"):
            self.assertEqual(status_value(rows_by_language[language]).upper(), "PASS")

        python_metadata = tomllib.loads(
            (REPO_ROOT / "packaging/python/pyproject.toml").read_text(encoding="utf-8")
        )
        rust_metadata = tomllib.loads(
            (REPO_ROOT / "packaging/rust/Cargo.toml").read_text(encoding="utf-8")
        )
        php_metadata = json.loads(
            (REPO_ROOT / "packaging/php/composer.json").read_text(encoding="utf-8")
        )
        makefile = (REPO_ROOT / "Makefile").read_text(encoding="utf-8")

        self.assertEqual(python_metadata["project"]["scripts"]["sshfling"], "sshfling.cli:main")
        self.assertIn("module github.com/GRWLX/sshfling/packaging/go", (REPO_ROOT / "packaging/go/go.mod").read_text(encoding="utf-8"))
        self.assertEqual(rust_metadata["package"]["name"], "sshfling-cli")
        self.assertEqual(php_metadata["name"], "grwlx/sshfling")
        self.assertTrue((REPO_ROOT / "packaging/ruby/sshfling.gemspec").is_file())

        for package in ("python", "go", "rust", "php", "ruby"):
            self.assertTrue((REPO_ROOT / f"packaging/build-{package}.sh").is_file())
            self.assertIn(f"package-{package}", makefile)

    def test_native_dotnet_language_and_perl_surfaces_are_supported(self) -> None:
        rows_by_language = {
            language_name(row): row for row in generate_language_support_matrix.LANGUAGE_SUPPORT
        }
        for language in (
            "C",
            "C++",
            "C#/.NET",
            "Visual Basic/.NET",
            "F#",
            "Perl",
            "CMake",
        ):
            self.assertEqual(status_value(rows_by_language[language]).upper(), "PASS")

        required_paths = (
            "packaging/native/CMakeLists.txt",
            "packaging/native/include/sshfling/sshfling.h",
            "packaging/native/include/sshfling/sshfling.hpp",
            "packaging/dotnet/SSHFling.Consumer.VB/Program.vb",
            "packaging/dotnet/SSHFling.Consumer.FSharp/Program.fs",
            "packaging/perl/Makefile.PL",
            "packaging/perl/lib/SSHFling.pm",
            "packaging/build-native-libraries.sh",
            "packaging/build-perl.sh",
        )
        for path in required_paths:
            self.assertTrue((REPO_ROOT / path).is_file(), path)

    def test_jvm_language_consumers_are_supported(self) -> None:
        rows_by_language = {
            language_name(row): row for row in generate_language_support_matrix.LANGUAGE_SUPPORT
        }
        source_paths = {
            "Kotlin": (
                "packaging/java/consumers/kotlin/src/main/kotlin/io/sshfling/validation/KotlinConsumer.kt",
                "packaging/java/consumers/kotlin-gradle/src/main/kotlin/io/sshfling/validation/KotlinGradleConsumer.kt",
            ),
            "Scala": (
                "packaging/java/consumers/scala/src/main/scala/io/sshfling/validation/ScalaConsumer.scala",
                "packaging/java/consumers/scala-gradle/src/main/scala/io/sshfling/validation/ScalaGradleConsumer.scala",
            ),
            "Groovy": (
                "packaging/java/consumers/groovy/src/main/groovy/io/sshfling/validation/GroovyConsumer.groovy",
                "packaging/java/consumers/groovy-gradle/src/main/groovy/io/sshfling/validation/GroovyGradleConsumer.groovy",
            ),
            "Clojure": (
                "packaging/java/consumers/clojure/src/main/clojure/io/sshfling/validation/clojure_consumer.clj",
                "packaging/java/consumers/clojure-gradle/src/main/clojure/io/sshfling/validation/clojure_gradle_consumer.clj",
            ),
        }
        for language, language_source_paths in source_paths.items():
            self.assertEqual(status_value(rows_by_language[language]).upper(), "PASS")
            for source_path in language_source_paths:
                self.assertTrue((REPO_ROOT / source_path).is_file(), source_path)

    def test_web_language_consumers_are_supported_or_gated(self) -> None:
        rows_by_language = {
            language_name(row): row for row in generate_language_support_matrix.LANGUAGE_SUPPORT
        }
        pass_sources = {
            "React/JSX": "packaging/node/consumers/react/src/StatusPage.jsx",
            "Vue": "packaging/node/consumers/vue/src/status-app.mjs",
            "Svelte": "packaging/node/consumers/svelte/src/Status.svelte",
            "Angular": "packaging/node/consumers/angular/src/server.ts",
            "Elm": "packaging/node/consumers/elm/src/Main.elm",
            "PureScript": "packaging/node/consumers/purescript/src/Main.purs",
            "Reason/ReScript": "packaging/node/consumers/rescript/src/Main.res",
            "HTML/CSS": "packaging/node/consumers/html-css/src/styles.css",
            "Dart": "packaging/node/consumers/dart/bin/sshfling_consumer.dart",
        }
        blocked_sources = {
            "Hack": "packaging/node/consumers/hack/src/main.hack",
            "CFML": "packaging/node/consumers/cfml/test.cfm",
        }

        for language, source_path in pass_sources.items():
            self.assertEqual(status_value(rows_by_language[language]).upper(), "PASS")
            self.assertTrue((REPO_ROOT / source_path).is_file(), source_path)
        for language, source_path in blocked_sources.items():
            self.assertEqual(status_value(rows_by_language[language]).upper(), "BLOCKED")
            self.assertTrue((REPO_ROOT / source_path).is_file(), source_path)

    def test_scripting_language_packages_are_supported_or_gated(self) -> None:
        rows_by_language = {
            language_name(row): row for row in generate_language_support_matrix.LANGUAGE_SUPPORT
        }
        pass_sources = {
            "Lua": "packaging/lua/lua/sshfling/init.lua",
            "Tcl": "packaging/tcl/sshfling.tcl",
            "AWK": "packaging/awk/sshfling.awk",
            "sed": "packaging/sed/sshfling-version.sed",
            "Zsh": "packaging/shell-languages/zsh/sshfling.zsh",
            "Fish": "packaging/shell-languages/fish/sshfling.fish",
            "Elvish": "packaging/shell-languages/elvish/sshfling.elv",
            "Nushell": "packaging/shell-languages/nushell/sshfling.nu",
            "PowerShell": "packaging/shell-languages/powershell/SSHFling.psm1",
        }
        blocked_sources = {
            "Guix Scheme": "packaging/guix-scheme/sshfling-package.scm",
        }

        for language, source_path in pass_sources.items():
            self.assertEqual(status_value(rows_by_language[language]).upper(), "PASS")
            self.assertTrue((REPO_ROOT / source_path).is_file(), source_path)
        for language, source_path in blocked_sources.items():
            self.assertEqual(status_value(rows_by_language[language]).upper(), "BLOCKED")
            self.assertTrue((REPO_ROOT / source_path).is_file(), source_path)

        makefile = (REPO_ROOT / "Makefile").read_text(encoding="utf-8")
        self.assertIn("package-scripting-languages:", makefile)
        self.assertTrue((REPO_ROOT / "packaging/build-scripting-languages.sh").is_file())

    def test_domain_language_inventory_is_explicitly_non_pass(self) -> None:
        rows_by_language = {
            language_name(row): row for row in generate_language_support_matrix.LANGUAGE_SUPPORT
        }
        manifest_path = REPO_ROOT / "packaging/domain-languages/manifest.tsv"
        with manifest_path.open(encoding="utf-8", newline="") as handle:
            domain_rows = list(csv.DictReader(handle, delimiter="\t"))

        self.assertEqual(len(domain_rows), 33)
        for domain_row in domain_rows:
            language = domain_row["language"]
            self.assertIn(
                status_value(rows_by_language[language]).upper(),
                {"BLOCKED", "NOT_APPLICABLE"},
                language,
            )
        makefile = (REPO_ROOT / "Makefile").read_text(encoding="utf-8")
        self.assertIn("audit-domain-languages:", makefile)

    def test_unsupported_languages_are_not_pass(self) -> None:
        unsupported_pass = [
            language_name(row)
            for row in generate_language_support_matrix.LANGUAGE_SUPPORT
            if is_unsupported(row) and status_value(row).upper() == "PASS"
        ]

        self.assertEqual(unsupported_pass, [])

    def test_render_markdown_includes_generated_markers_and_table(self) -> None:
        markdown = generate_language_support_matrix.render_markdown()

        self.assertIn("<!-- BEGIN GENERATED LANGUAGE SUPPORT MATRIX -->", markdown)
        self.assertIn("<!-- END GENERATED LANGUAGE SUPPORT MATRIX -->", markdown)
        self.assertRegex(markdown, re.compile(r"^\|[^\n]*Language[^\n]*\|", re.MULTILINE))
        self.assertRegex(markdown, re.compile(r"^\|[ :|-]+\|$", re.MULTILINE))


if __name__ == "__main__":
    unittest.main()
