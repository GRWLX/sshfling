from __future__ import annotations

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]


class PublicWebSafetyTests(unittest.TestCase):
    def run_builder(self, package_dist: Path, public_dir: Path) -> subprocess.CompletedProcess[str]:
        environment = os.environ.copy()
        environment.update(
            {
                "VERSION": "0.1.16",
                "REPOSITORY": "GRWLX/sshfling",
                "OWNER": "GRWLX",
            }
        )
        return subprocess.run(
            [
                "bash",
                str(REPO_ROOT / "packaging/build-public-web.sh"),
                str(package_dist),
                str(public_dir),
            ],
            cwd=REPO_ROOT,
            env=environment,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )

    def test_rejects_repository_root_as_recursive_output(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            marker = REPO_ROOT / "Makefile"
            before = marker.read_bytes()
            result = self.run_builder(Path(temporary) / "packages", REPO_ROOT)
            self.assertEqual(result.returncode, 2)
            self.assertIn("Refusing", result.stderr)
            self.assertEqual(marker.read_bytes(), before)

    def test_rejects_output_overlapping_package_input(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            package_dist = Path(temporary) / "packages"
            package_dist.mkdir()
            result = self.run_builder(package_dist, package_dist / "public")
            self.assertEqual(result.returncode, 2)
            self.assertIn("overlapping", result.stderr)


if __name__ == "__main__":
    unittest.main()
