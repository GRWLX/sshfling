from __future__ import annotations

import os
import re
import shlex
import stat
import struct
import subprocess
import tarfile
import tempfile
import time
import unittest
import zipfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
INVENTORY = REPO_ROOT / "packaging" / "list-language-release-artifacts.sh"
SCRIPTING_BUILDER = REPO_ROOT / "packaging" / "build-scripting-languages.sh"
VERSION = "1.2.3"
SOURCE_DATE_EPOCH = 1_700_000_001


def inventory(group: str) -> list[str]:
    completed = subprocess.run(
        ["bash", str(INVENTORY), VERSION, group],
        cwd=REPO_ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    return completed.stdout.splitlines()


def shell_function(source: str, name: str) -> str:
    match = re.search(
        rf"^{re.escape(name)}\(\) \{{\n.*?^\}}\n",
        source,
        flags=re.MULTILINE | re.DOTALL,
    )
    if match is None:
        raise AssertionError(f"shell function not found: {name}")
    return match.group(0)


def run_shell(script: str) -> None:
    subprocess.run(
        ["bash"],
        cwd=REPO_ROOT,
        input=script,
        check=True,
        capture_output=True,
        text=True,
    )


class LanguageReleaseArtifactTests(unittest.TestCase):
    def test_scripting_tar_helper_normalizes_metadata_and_bytes(self) -> None:
        source = SCRIPTING_BUILDER.read_text(encoding="utf-8")
        helper = shell_function(source, "deterministic_tar_gz")
        for fragment in (
            "--sort=name",
            '--mtime="@$source_date_epoch"',
            "--owner=0 --group=0 --numeric-owner",
            "--format=posix",
            "--pax-option=delete=atime,delete=ctime",
            "gzip -n -9",
        ):
            self.assertIn(fragment, helper)

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archives: list[Path] = []
            entries = {
                "z-executable": b"#!/bin/sh\nexit 0\n",
                "a-file": b"alpha\n",
                "nested/middle": b"middle\n",
            }
            for index, order in enumerate((tuple(entries), tuple(reversed(entries)))):
                parent = root / f"input-{index}"
                bundle = parent / "bundle"
                bundle.mkdir(parents=True)
                for relative in order:
                    path = bundle / relative
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_bytes(entries[relative])
                (bundle / "z-executable").chmod(0o755)
                (bundle / "link-to-a").symlink_to("a-file")
                for path in (bundle, *bundle.rglob("*")):
                    os.utime(
                        path,
                        (100 + index, 100 + index),
                        follow_symlinks=False,
                    )

                archive = root / f"output-{index}" / "bundle.tar.gz"
                archive.parent.mkdir()
                archives.append(archive)
                run_shell(
                    "set -Eeuo pipefail\n"
                    f"source_date_epoch={SOURCE_DATE_EPOCH}\n"
                    f"{helper}\n"
                    "deterministic_tar_gz "
                    f"{shlex.quote(str(parent))} bundle {shlex.quote(str(archive))}\n"
                )

            first_bytes = archives[0].read_bytes()
            self.assertEqual(first_bytes, archives[1].read_bytes())
            self.assertEqual(first_bytes[:3], b"\x1f\x8b\x08")
            self.assertEqual(first_bytes[3] & 0x18, 0)
            self.assertEqual(int.from_bytes(first_bytes[4:8], "little"), 0)

            with tarfile.open(archives[0], "r:gz") as archive:
                members = archive.getmembers()
            self.assertEqual(
                [member.name for member in members],
                sorted(member.name for member in members),
            )
            self.assertTrue(all(member.uid == 0 and member.gid == 0 for member in members))
            self.assertTrue(all(member.mtime == SOURCE_DATE_EPOCH for member in members))
            self.assertTrue(
                all(
                    "atime" not in member.pax_headers
                    and "ctime" not in member.pax_headers
                    for member in members
                )
            )

    def test_scripting_archive_path_repeats_compares_and_records_sha256(self) -> None:
        source = SCRIPTING_BUILDER.read_text(encoding="utf-8")
        archive_function = shell_function(source, "archive_and_extract")
        self.assertIn('source_date_epoch="${SOURCE_DATE_EPOCH:-0}"', source)
        self.assertIn('export SOURCE_DATE_EPOCH="$source_date_epoch"', source)
        self.assertEqual(archive_function.count("deterministic_tar_gz "), 2)
        self.assertIn('cmp "$archive_candidate" "$repeat_archive"', archive_function)
        self.assertIn('archive_sha="$(sha256sum "$archive"', archive_function)
        self.assertIn("sha256=$archive_sha", archive_function)
        self.assertIn("repeat_build=identical", archive_function)

    def test_lua_rock_normalizer_removes_host_metadata(self) -> None:
        source = SCRIPTING_BUILDER.read_text(encoding="utf-8")
        helper = shell_function(source, "normalize_lua_rock")

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            inputs = [root / "first.all.rock", root / "second.all.rock"]
            outputs = [root / "normalized-first.all.rock", root / "normalized-second.all.rock"]
            payloads = {
                "lua/module.lua": b"return { version = '1.2.3' }\n",
                "bin/": b"",
                "bin/sshfling": b"#!/bin/sh\nexit 0\n",
            }

            for index, path in enumerate(inputs):
                order = tuple(payloads) if index == 0 else tuple(reversed(payloads))
                with zipfile.ZipFile(path, "w") as archive:
                    archive.comment = f"host-{index}".encode()
                    for name in order:
                        info = zipfile.ZipInfo(name, (2024 + index, 2, 3, 4, 5, 6))
                        info.create_system = 3
                        if name.endswith("/"):
                            mode = stat.S_IFDIR | (0o700 if index == 0 else 0o775)
                            compression = zipfile.ZIP_STORED
                        elif name.startswith("bin/"):
                            mode = stat.S_IFREG | (0o755 if index == 0 else 0o775)
                            compression = zipfile.ZIP_DEFLATED
                        else:
                            mode = stat.S_IFREG | (0o600 if index == 0 else 0o664)
                            compression = zipfile.ZIP_DEFLATED
                        info.external_attr = (mode & 0xFFFF) << 16
                        info.extra = struct.pack("<HHBI", 0x5455, 5, 1, 100 + index)
                        info.comment = b"entry-host-data"
                        archive.writestr(info, payloads[name], compress_type=compression)

            run_shell(
                "set -Eeuo pipefail\n"
                f"source_date_epoch={SOURCE_DATE_EPOCH}\n"
                f"{helper}\n"
                f"normalize_lua_rock {shlex.quote(str(inputs[0]))} "
                f"{shlex.quote(str(outputs[0]))}\n"
                f"normalize_lua_rock {shlex.quote(str(inputs[1]))} "
                f"{shlex.quote(str(outputs[1]))}\n"
            )

            self.assertEqual(outputs[0].read_bytes(), outputs[1].read_bytes())
            expected_time = time.gmtime(SOURCE_DATE_EPOCH)
            expected_date_time = (
                expected_time.tm_year,
                expected_time.tm_mon,
                expected_time.tm_mday,
                expected_time.tm_hour,
                expected_time.tm_min,
                expected_time.tm_sec - (expected_time.tm_sec % 2),
            )
            with zipfile.ZipFile(outputs[0]) as archive:
                infos = archive.infolist()
                self.assertEqual(archive.comment, b"")
                self.assertIsNone(archive.testzip())
                self.assertEqual(
                    [info.filename for info in infos],
                    sorted(info.filename for info in infos),
                )
                self.assertTrue(all(info.date_time == expected_date_time for info in infos))
                self.assertTrue(all(info.extra == b"" and info.comment == b"" for info in infos))
                modes = {
                    info.filename: (info.external_attr >> 16) & 0xFFFF for info in infos
                }
                self.assertEqual(stat.S_IMODE(modes["bin/"]), 0o755)
                self.assertEqual(stat.S_IMODE(modes["bin/sshfling"]), 0o755)
                self.assertEqual(stat.S_IMODE(modes["lua/module.lua"]), 0o644)
                self.assertEqual(archive.read("bin/sshfling"), payloads["bin/sshfling"])

    def test_lua_rock_is_repeat_packed_normalized_and_evidenced(self) -> None:
        source = SCRIPTING_BUILDER.read_text(encoding="utf-8")
        runtime_function = shell_function(source, "validate_lua_runtime")
        self.assertEqual(runtime_function.count("pack_lua_rock "), 2)
        self.assertEqual(runtime_function.count("normalize_lua_rock "), 2)
        self.assertIn('cmp "$normalized_primary" "$normalized_repeat"', runtime_function)
        self.assertIn("sha256=$rock_sha", runtime_function)
        self.assertIn("repeat_build=identical", runtime_function)
        self.assertIn("metadata=normalized", runtime_function)
        self.assertIn("validate_packed_lua_rock", runtime_function)

    def test_inventory_groups_are_complete_unique_and_versioned(self) -> None:
        scripting = inventory("scripting")
        functional = inventory("functional")
        systems = inventory("systems")
        catalog = inventory("catalog")
        all_files = inventory("all")

        self.assertEqual(len(scripting), 12)
        self.assertEqual(len(functional), 21)
        self.assertEqual(len(systems), 20)
        self.assertEqual(catalog, functional + systems)
        self.assertEqual(all_files, scripting + catalog)
        self.assertEqual(len(all_files), 53)
        self.assertEqual(len(all_files), len(set(all_files)))
        self.assertTrue(all(VERSION in name for name in all_files))

    def test_inventory_contains_batch_evidence_and_representative_libraries(self) -> None:
        files = set(inventory("all"))
        expected = {
            f"sshfling-haskell-{VERSION}.tar.gz",
            f"sshfling-julia-{VERSION}.tar.gz",
            f"sshfling-erlang-{VERSION}.tar.gz",
            f"sshfling-swift-{VERSION}.tar.gz",
            f"sshfling-webassembly-wasi-{VERSION}.tar.gz",
            f"sshfling-functional-languages-{VERSION}-validation.tsv",
            f"sshfling-systems-languages-{VERSION}-validation.tsv",
            f"sshfling-scripting-languages-{VERSION}-validation.tsv",
        }
        self.assertTrue(expected <= files)

    def test_release_paths_use_the_canonical_inventory(self) -> None:
        makefile = (REPO_ROOT / "Makefile").read_text(encoding="utf-8")
        self.assertIn("package-language-catalog:", makefile)
        self.assertIn("--allow-blocked", makefile)

        for relative in (
            ".github/workflows/release-packages.yml",
            ".github/workflows/public-package-web.yml",
            "packaging/build-public-web.sh",
            "packaging/verify-public-web.sh",
            "tools/generate_release_evidence.py",
        ):
            content = (REPO_ROOT / relative).read_text(encoding="utf-8")
            self.assertIn("list-language-release-artifacts.sh", content, relative)

    def test_unknown_group_fails_closed(self) -> None:
        completed = subprocess.run(
            ["bash", str(INVENTORY), VERSION, "unknown"],
            cwd=REPO_ROOT,
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(completed.returncode, 2)
        self.assertIn("unknown language artifact group", completed.stderr)


if __name__ == "__main__":
    unittest.main()
