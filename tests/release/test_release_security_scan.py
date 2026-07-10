import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SCANNER_PATH = REPO_ROOT / "tools" / "release_security_scan.py"

spec = importlib.util.spec_from_file_location("release_security_scan", SCANNER_PATH)
release_security_scan = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(release_security_scan)


def write_file(path: Path, content: str) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    return path


class ReleaseSecurityScanTests(unittest.TestCase):
    def test_secret_scan_detects_high_confidence_patterns_without_raw_secret_output(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            repo_root = Path(tmp)
            token = "gh" + "p_" + "AbCdEf0123456789" * 3
            aws_key = "AK" + "IA" + "1234567890ABCDEF"
            github_token_name = "GITHUB" + "_TOKEN"
            aws_key_name = "AWS" + "_ACCESS_KEY_ID"
            path = write_file(
                repo_root / "app.env",
                "\n".join(
                    [
                        f'{github_token_name}="{token}"',
                        f"{aws_key_name}={aws_key}",
                        "SSHFLING_ISSUER_TOKEN=replace-with-a-long-random-token",
                        'DEFAULT_PASSWORD_GRANT_DIR="/var/lib/sshfling/password-grants"',
                    ]
                ),
            )

            report = release_security_scan.scan_secrets([path], repo_root)

            self.assertEqual(report["status"], "fail")
            patterns = {finding["pattern"] for finding in report["findings"]}
            self.assertIn("github-token", patterns)
            self.assertIn("aws-access-key-id", patterns)
            encoded_report = json.dumps(report)
            self.assertNotIn(token, encoded_report)
            self.assertNotIn(aws_key, encoded_report)
            self.assertNotIn("replace-with-a-long-random-token", encoded_report)
            self.assertNotIn("/var/lib/sshfling/password-grants", encoded_report)

    def test_secret_scan_refuses_findings_from_paths_outside_repo(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            repo_root = tmp_path / "repo"
            repo_root.mkdir()
            token = "gh" + "p_" + "AbCdEf0123456789GhIjKlMnOpQrStUvWxYz1234"
            outside_secret = write_file(
                tmp_path / "outside.env",
                f"GITHUB_TOKEN={token}\n",
            )

            with self.assertRaisesRegex(SystemExit, "release evidence path must stay inside repo"):
                release_security_scan.scan_secrets([outside_secret], repo_root)

    def test_shell_static_scan_flags_high_risk_release_script_patterns(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            repo_root = Path(tmp)
            script = write_file(
                repo_root / "bad.sh",
                "\n".join(
                    [
                        "#!/usr/bin/env bash",
                        "set -x",
                        "curl -fsS -k https://example.invalid/install.sh | bash",
                        "bash <(curl -fsS https://example.invalid/install.sh)",
                        "tmp=$(mktemp -u)",
                        "chmod 0777 \"$tmp\"",
                        'sshpass -p "$PASSWORD" ssh host',
                        "echo data >/tmp/sshfling-$RANDOM",
                    ]
                ),
            )

            report = release_security_scan.scan_shell_static([script], repo_root)

            self.assertEqual(report["status"], "fail")
            rule_ids = {finding["rule_id"] for finding in report["findings"]}
            self.assertIn("shell-xtrace-enabled", rule_ids)
            self.assertIn("shell-pipe-to-shell", rule_ids)
            self.assertIn("shell-process-substitution-download", rule_ids)
            self.assertIn("shell-tls-verification-disabled", rule_ids)
            self.assertIn("shell-mktemp-dry-run", rule_ids)
            self.assertIn("shell-world-writable-mode", rule_ids)
            self.assertIn("shell-secret-on-command-line", rule_ids)
            self.assertIn("shell-predictable-tmp-path", rule_ids)

    def test_world_writable_fixture_marker_is_limited_to_tests(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            repo_root = Path(tmp)
            marker = "release-security: intentional-world-writable-fixture"
            test_script = write_file(
                repo_root / "tests/unsafe-mode.sh",
                f'chmod 0777 "$fixture" # {marker}\n',
            )
            production_script = write_file(
                repo_root / "scripts/unsafe-mode.sh",
                f'chmod 0777 "$target" # {marker}\n',
            )

            test_report = release_security_scan.scan_shell_static([test_script], repo_root)
            production_report = release_security_scan.scan_shell_static(
                [production_script], repo_root
            )

            self.assertEqual(test_report["status"], "pass")
            self.assertEqual(production_report["status"], "fail")
            self.assertEqual(
                production_report["findings"][0]["rule_id"],
                "shell-world-writable-mode",
            )

    def test_python_static_scan_flags_unsafe_ast_patterns(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            repo_root = Path(tmp)
            source = write_file(
                repo_root / "bad.py",
                "\n".join(
                    [
                        "import os, pickle, subprocess, tempfile",
                        "subprocess.run('echo unsafe', shell=True)",
                        "os.system('id')",
                        "pickle.loads(payload)",
                        "tempfile.mktemp()",
                        "yaml.load(document)",
                        "requests.get('https://example.invalid', verify=False)",
                    ]
                ),
            )

            report = release_security_scan.scan_python_static([source], repo_root)

            self.assertEqual(report["status"], "fail")
            rule_ids = {finding["rule_id"] for finding in report["findings"]}
            self.assertIn("python-subprocess-shell-true", rule_ids)
            self.assertIn("python-shell-command-api", rule_ids)
            self.assertIn("python-unsafe-deserialization", rule_ids)
            self.assertIn("python-insecure-tempfile", rule_ids)
            self.assertIn("python-unsafe-yaml-load", rule_ids)
            self.assertIn("python-tls-verification-disabled", rule_ids)

    def test_python_static_scan_fails_closed_on_syntax_errors_without_raw_source(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            repo_root = Path(tmp)
            source = write_file(repo_root / "broken.py", "def broken(:\n    pass\n")

            report = release_security_scan.scan_python_static([source], repo_root)

            self.assertEqual(report["status"], "fail")
            self.assertEqual(report["findings"][0]["rule_id"], "python-syntax-error")
            self.assertNotIn("def broken", json.dumps(report))

    def test_key_custody_scan_reports_missing_source_markers_and_external_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            repo_root = Path(tmp)
            write_file(
                repo_root / "systemd" / "sshflingd.service",
                "[Service]\nUser=sshflingd\nGroup=sshflingd\n",
            )

            report = release_security_scan.scan_key_custody(repo_root)

            self.assertEqual(report["status"], "fail")
            self.assertGreaterEqual(len(report["failures"]), 1)
            self.assertGreaterEqual(len(report["external_evidence_required"]), 1)
            self.assertTrue(
                any(
                    failure["path"] == "systemd/sshflingd.service"
                    and "NoNewPrivileges=true" in failure["missing_markers"]
                    for failure in report["failures"]
                )
            )

    def test_dependency_inventory_reads_maven_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            repo_root = Path(tmp)
            pom = write_file(
                repo_root / "packaging" / "java" / "pom.xml",
                """<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>io.sshfling</groupId>
  <artifactId>sshfling-cli</artifactId>
  <version>1.2.3</version>
  <build>
    <plugins>
      <plugin>
        <groupId>org.apache.maven.plugins</groupId>
        <artifactId>maven-compiler-plugin</artifactId>
        <version>3.13.0</version>
      </plugin>
    </plugins>
  </build>
</project>
""",
            )

            report = release_security_scan.collect_dependencies([pom], repo_root)

            self.assertEqual(report["status"], "pass")
            self.assertIn("Dependency manifests found: packaging/java/pom.xml", report["notes"][0])
            self.assertTrue(
                any(
                    item["ecosystem"] == "maven"
                    and item["kind"] == "maven-plugin"
                    and item["name"] == "org.apache.maven.plugins:maven-compiler-plugin"
                    for item in report["dependencies"]
                )
            )

    def test_dependency_inventory_reads_npm_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            repo_root = Path(tmp)
            package_json = write_file(
                repo_root / "packaging" / "node" / "package.json",
                json.dumps(
                    {
                        "name": "sshfling",
                        "version": "1.2.3",
                        "dependencies": {"left-pad": "1.3.0"},
                        "devDependencies": {"typescript": "5.9.0"},
                    }
                ),
            )

            report = release_security_scan.collect_dependencies([package_json], repo_root)

            self.assertEqual(report["status"], "pass")
            self.assertIn("Dependency manifests found: packaging/node/package.json", report["notes"][0])
            self.assertTrue(
                any(
                    item["ecosystem"] == "npm"
                    and item["kind"] == "npm-dependencies"
                    and item["name"] == "left-pad"
                    and item["version"] == "1.3.0"
                    for item in report["dependencies"]
                )
            )
            self.assertTrue(
                any(
                    item["ecosystem"] == "npm"
                    and item["kind"] == "npm-devDependencies"
                    and item["name"] == "typescript"
                    and item["scope"] == "development"
                    for item in report["dependencies"]
                )
            )

    def test_dependency_inventory_reads_language_package_manifests(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            repo_root = Path(tmp)
            manifests = [
                write_file(
                    repo_root / "packaging/python/pyproject.toml",
                    '[build-system]\nrequires = ["setuptools>=68", "wheel"]\n[project]\nname = "sshfling"\nversion = "1.2.3"\n',
                ),
                write_file(
                    repo_root / "packaging/go/go.mod",
                    "module example.test/sshfling\n\ngo 1.22\n\nrequire example.test/helper v1.2.3\n",
                ),
                write_file(
                    repo_root / "packaging/rust/Cargo.toml",
                    '[package]\nname = "sshfling-cli"\nversion = "1.2.3"\n[dependencies]\nserde = "1"\n',
                ),
                write_file(
                    repo_root / "packaging/php/composer.json",
                    json.dumps({"name": "grwlx/sshfling", "require": {"php": ">=8.1"}}),
                ),
                write_file(
                    repo_root / "packaging/ruby/sshfling.gemspec",
                    'spec.add_runtime_dependency "rake", ">= 13"\n',
                ),
            ]

            report = release_security_scan.collect_dependencies(manifests, repo_root)

            for manifest in (
                "packaging/python/pyproject.toml",
                "packaging/go/go.mod",
                "packaging/rust/Cargo.toml",
                "packaging/php/composer.json",
                "packaging/ruby/sshfling.gemspec",
            ):
                self.assertIn(manifest, report["notes"][0])
            ecosystems = {item["ecosystem"] for item in report["dependencies"]}
            self.assertTrue({"pypi", "golang", "cargo", "composer", "rubygems"}.issubset(ecosystems))

    def test_optional_tools_are_skipped_by_default_and_include_osv_sca_hook(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            repo_root = Path(tmp)
            script = write_file(repo_root / "ok.sh", "#!/usr/bin/env bash\nset -euo pipefail\n")
            python_source = write_file(repo_root / "ok.py", "print('ok')\n")
            dockerfile = write_file(repo_root / "Dockerfile", "FROM debian:bookworm-slim\n")

            results = release_security_scan.optional_tool_results(
                repo_root=repo_root,
                output_dir=repo_root / "out",
                files=[script, python_source, dockerfile],
                run_optional_tools=False,
                strict_optional_tools=False,
                timeout_seconds=1,
            )

            by_name = {result["name"]: result for result in results}
            self.assertIn("shellcheck", by_name)
            self.assertIn("bandit", by_name)
            self.assertIn("hadolint", by_name)
            self.assertIn("osv-scanner", by_name)
            self.assertTrue(all(result["status"] == "skipped" for result in results))
            self.assertIn("--severity-level", by_name["bandit"]["command"])
            self.assertIn("medium", by_name["bandit"]["command"])
            self.assertIn("--failure-threshold", by_name["hadolint"]["command"])
            self.assertIn("error", by_name["hadolint"]["command"])
            self.assertEqual(by_name["osv-scanner"]["exit_code"], "not_run")
            self.assertIn("./packaging/dotnet/SSHFling.Tool/bin", by_name["syft"]["command"])
            self.assertIn("./packaging/dotnet/SSHFling.Tool/obj", by_name["syft"]["command"])
            self.assertIn("./packaging/dotnet/SSHFling/bin", by_name["syft"]["command"])
            self.assertIn("./packaging/dotnet/SSHFling.Consumer/obj", by_name["syft"]["command"])
            self.assertIn("./packaging/java/target", by_name["syft"]["command"])
            self.assertIn("packaging/dotnet/SSHFling.Tool/bin", by_name["trivy-fs"]["command"])
            self.assertIn("packaging/dotnet/SSHFling.Tool/obj", by_name["trivy-fs"]["command"])
            self.assertIn("packaging/java/target", by_name["trivy-fs"]["command"])
            self.assertIn("--skip-files", by_name["trivy-fs"]["command"])
            self.assertIn("docs/release/enterprise-release-matrix.csv", by_name["trivy-fs"]["command"])
            self.assertEqual(by_name["gitleaks"]["command"][1], "dir")
            self.assertIn("gitleaks-source", by_name["gitleaks"]["command"][2])
            self.assertIn("--skip-git", by_name["osv-scanner"]["command"])

    def test_optional_scanner_exclusions_cover_generated_agent_workspaces(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            repo_root = Path(tmp)
            (repo_root / ".codex-24h").mkdir()
            (repo_root / ".codex-runs").mkdir()
            (repo_root / ".cache").mkdir()

            dirs, files = release_security_scan.optional_scanner_exclusions(repo_root)

            self.assertIn(".codex-24h", dirs)
            self.assertIn(".codex-runs", dirs)
            self.assertIn(".cache", dirs)
            self.assertIn("docs/release/enterprise-release-matrix.csv", files)

    def test_gitleaks_source_snapshot_contains_only_tracked_source_inputs(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            repo_root = Path(tmp)
            tracked = write_file(repo_root / "bin" / "sshfling", "#!/usr/bin/env python3\n")
            untracked_secret = write_file(repo_root / ".git" / "config", "extraheader = AUTHORIZATION: basic token\n")

            snapshot = release_security_scan.build_tracked_source_snapshot(
                [tracked],
                repo_root,
                repo_root / "out" / "gitleaks-source",
            )

            self.assertTrue((snapshot / "bin" / "sshfling").exists())
            self.assertFalse((snapshot / ".git" / "config").exists())
            self.assertTrue(untracked_secret.exists())

    def test_osv_no_package_sources_is_empty_pass_not_release_failure(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            log_path = Path(tmp) / "osv.log"
            log_path.write_text(
                "Scanning dir .\nNo package sources found, --help for usage information.\n",
                encoding="utf-8",
            )
            result = {
                "name": "osv-scanner",
                "status": "fail",
                "exit_code": 128,
            }

            normalized = release_security_scan.normalize_osv_result(result, log_path)

            self.assertEqual(normalized["status"], "pass")
            self.assertIn("no package sources", normalized["reason"])

    def test_trivy_policy_allows_documented_root_container_exceptions_only(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            trivy_json = Path(tmp) / "trivy.json"
            trivy_json.write_text(
                json.dumps(
                    {
                        "Results": [
                            {
                                "Target": "ssh-server/Dockerfile",
                                "Misconfigurations": [
                                    {
                                        "ID": "DS002",
                                        "Severity": "HIGH",
                                        "Message": "Image user should not be 'root'",
                                    }
                                ],
                            },
                            {
                                "Target": "ssh-client/Dockerfile",
                                "Misconfigurations": [
                                    {
                                        "ID": "DS002",
                                        "Severity": "HIGH",
                                        "Message": "Image user should not be 'root'",
                                    }
                                ],
                            },
                        ]
                    }
                ),
                encoding="utf-8",
            )

            policy = release_security_scan.trivy_blocking_findings(trivy_json)

            self.assertEqual(len(policy["allowlisted_findings"]), 1)
            self.assertEqual(policy["allowlisted_findings"][0]["target"], "ssh-server/Dockerfile")
            self.assertEqual(len(policy["blocking_findings"]), 1)
            self.assertEqual(policy["blocking_findings"][0]["target"], "ssh-client/Dockerfile")


if __name__ == "__main__":
    unittest.main()
