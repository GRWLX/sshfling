from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
TOOL_PATH = REPO_ROOT / "tools/official_distro_readiness.py"


def load_tool():
    spec = importlib.util.spec_from_file_location("official_distro_readiness", TOOL_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


readiness = load_tool()


class OfficialDistroReadinessTests(unittest.TestCase):
    def test_current_license_blocks_official_distro_submission(self) -> None:
        license_check = readiness.license_status()

        self.assertEqual(license_check.status, readiness.BLOCKED)
        self.assertIn("proprietary", license_check.evidence)
        self.assertIn("open-source license", license_check.next_action)

    def test_current_generated_rpm_license_is_not_fedora_ready(self) -> None:
        rpm_check = readiness.generated_rpm_license_status()

        self.assertEqual(rpm_check.status, readiness.BLOCKED)
        self.assertIn("LicenseRef-SSHFling-Commercial", rpm_check.evidence)

    def test_report_records_draft_debian_and_fedora_source_packaging(self) -> None:
        checks = {item.area: item for item in readiness.checks()}

        self.assertEqual(checks["Debian/Ubuntu source packaging"].status, readiness.WARN)
        self.assertIn("draft", checks["Debian/Ubuntu source packaging"].evidence)
        self.assertEqual(checks["Debian/Ubuntu maintainer metadata"].status, readiness.WARN)
        self.assertIn("placeholder", checks["Debian/Ubuntu maintainer metadata"].evidence)
        self.assertEqual(checks["Fedora/EPEL source packaging"].status, readiness.WARN)
        self.assertIn("draft", checks["Fedora/EPEL source packaging"].evidence)
        self.assertEqual(checks["Fedora/EPEL spec license metadata"].status, readiness.BLOCKED)
        self.assertIn("LicenseRef-SSHFling-Commercial", checks["Fedora/EPEL spec license metadata"].evidence)
        self.assertEqual(checks["Official distro draft validation"].status, readiness.PASS)
        self.assertIn("Repeatable", checks["Official distro draft validation"].evidence)

    def test_markdown_report_has_stable_decision_gate(self) -> None:
        rendered = readiness.render_markdown(readiness.checks())

        self.assertIn("# Official Distro Repository Readiness", rendered)
        self.assertIn("The repository is not ready", rendered)
        self.assertIn("| License | BLOCKED |", rendered)


if __name__ == "__main__":
    unittest.main()
