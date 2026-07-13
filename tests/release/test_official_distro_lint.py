from __future__ import annotations

import importlib.util
import io
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
TOOL_PATH = REPO_ROOT / "tools/validate_official_distro_lint.py"


def load_tool():
    spec = importlib.util.spec_from_file_location("validate_official_distro_lint", TOOL_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


validator = load_tool()


def quiet_call(func, *args):
    with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
        return func(*args)


class OfficialDistroLintTests(unittest.TestCase):
    def test_lintian_allows_known_external_blockers(self) -> None:
        text = "\n".join(
            [
                "E: sshfling: bogus-mail-host Maintainer root@localhost",
                "E: sshfling changes: root-in-contact Maintainer \"SSHFling Maintainers\" <root@localhost>",
                "W: sshfling: initial-upload-closes-no-bugs [usr/share/doc/sshfling/changelog.Debian.gz:1]",
            ]
        )

        with tempfile.TemporaryDirectory() as tmp:
            report = Path(tmp) / "lintian.log"
            report.write_text(text, encoding="utf-8")
            self.assertEqual(quiet_call(validator.validate_lintian, report), 0)

    def test_lintian_rejects_unexpected_tags(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            report = Path(tmp) / "lintian.log"
            report.write_text("E: sshfling: no-manual-page [usr/bin/sshfling]\n", encoding="utf-8")
            self.assertEqual(quiet_call(validator.validate_lintian, report), 1)

    def test_lintian_rejects_nonzero_without_parseable_tags(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            report = Path(tmp) / "lintian.log"
            report.write_text("internal error\n", encoding="utf-8")
            self.assertEqual(quiet_call(validator.validate_lintian, report, 2), 1)

    def test_autopkgtest_summary_allows_backend_nonzero_when_tests_pass(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            summary = Path(tmp) / "summary"
            summary.write_text("smoke PASS (superficial)\n", encoding="utf-8")
            self.assertEqual(quiet_call(validator.validate_autopkgtest, summary, 8), 0)

    def test_autopkgtest_summary_rejects_failed_tests(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            summary = Path(tmp) / "summary"
            summary.write_text("smoke FAIL non-zero exit status 1\n", encoding="utf-8")
            self.assertEqual(quiet_call(validator.validate_autopkgtest, summary, 0), 1)


if __name__ == "__main__":
    unittest.main()
