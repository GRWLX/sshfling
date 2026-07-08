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
            self.assertIn("packaging/dotnet/SSHFling.Tool/bin", by_name["trivy-fs"]["command"])
            self.assertIn("packaging/dotnet/SSHFling.Tool/obj", by_name["trivy-fs"]["command"])

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
