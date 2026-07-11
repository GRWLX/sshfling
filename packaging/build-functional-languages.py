#!/usr/bin/env python3
"""Focused native-package validator for the standalone language launchers."""

from __future__ import annotations

import argparse
import ast
import csv
import datetime as dt
import fcntl
import gzip
import hashlib
import io
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tarfile
import tempfile
import tomllib
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Iterable


if sys.version_info < (3, 11):
    raise SystemExit("build-functional-languages: Python >= 3.11 is required")


REPO_ROOT = Path(__file__).resolve().parent.parent
MANIFESTS = (
    REPO_ROOT / "packaging/functional-languages/languages.tsv",
    REPO_ROOT / "packaging/scientific-languages/languages.tsv",
    REPO_ROOT / "packaging/beam-languages/languages.tsv",
)
EXPECTED_VERSION = "0.1.19"
DIST_ROOT = REPO_ROOT / "dist"
DEFAULT_EVIDENCE = DIST_ROOT / f"sshfling-functional-languages-{EXPECTED_VERSION}-validation.tsv"
EXPECTED_FIELDS = (
    "id",
    "label",
    "tools",
    "runner",
    "root",
    "metadata",
    "api",
    "consumer",
    "bundle",
)
UNSET_RUNTIME_ENV = (
    "SSHFLING_RUNTIME",
    "SSHFLING_TEMPLATE_DIR",
    "SSHFLING_PACKAGE_ROOT",
    "SSHFLING_PYTHON",
)
SOURCE_IGNORES = (
    ".git",
    ".DS_Store",
    "__pycache__",
    "*.pyc",
    "dist-newstyle",
    "_build",
    "target",
)


@dataclass(frozen=True)
class Language:
    identifier: str
    label: str
    tools: str
    runner: str
    package_dir: Path
    metadata: tuple[str, ...]
    api: tuple[str, ...]
    consumer: str
    bundle: str


class ValidationFailure(RuntimeError):
    pass


class Evidence:
    fields = (
        "timestamp_utc",
        "language",
        "result",
        "phase",
        "status",
        "cwd",
        "command",
        "stdout",
        "stderr",
        "detail",
    )

    def __init__(self, path: Path):
        self.path = path.resolve()
        self.path.parent.mkdir(parents=True, exist_ok=True)
        temporary = self.path.with_name(f".{self.path.name}.tmp")
        with temporary.open("w", encoding="utf-8", newline="") as stream:
            csv.writer(stream, delimiter="\t", lineterminator="\n").writerow(self.fields)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, self.path)

    @staticmethod
    def _bounded(value: str, limit: int = 65536) -> str:
        if len(value) <= limit:
            return value
        digest = hashlib.sha256(value.encode("utf-8", "replace")).hexdigest()
        return f"{value[:limit]}\n[truncated sha256={digest} bytes={len(value.encode())}]"

    def record(
        self,
        language: str,
        result: str,
        phase: str,
        *,
        status: str | int = "",
        cwd: Path | str = "",
        command: str = "",
        stdout: str = "",
        stderr: str = "",
        detail: str = "",
    ) -> None:
        row = (
            dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
            language,
            result,
            phase,
            str(status),
            str(cwd),
            command,
            self._bounded(stdout),
            self._bounded(stderr),
            detail,
        )
        with self.path.open("a", encoding="utf-8", newline="") as stream:
            csv.writer(stream, delimiter="\t", lineterminator="\n").writerow(row)
            stream.flush()
            os.fsync(stream.fileno())


def source_constants(path: Path) -> dict[str, object]:
    tree = ast.parse(path.read_bytes(), filename=str(path))
    constants: dict[str, object] = {}
    for node in tree.body:
        if not isinstance(node, ast.Assign) or len(node.targets) != 1:
            continue
        target = node.targets[0]
        if isinstance(target, ast.Name):
            try:
                constants[target.id] = ast.literal_eval(node.value)
            except (ValueError, TypeError):
                pass
    return constants


def load_languages() -> list[Language]:
    languages: list[Language] = []
    seen: set[str] = set()
    declared_by_group: dict[Path, set[str]] = {}
    for manifest in MANIFESTS:
        with manifest.open(newline="", encoding="utf-8") as stream:
            reader = csv.DictReader(stream, delimiter="\t")
            if tuple(reader.fieldnames or ()) != EXPECTED_FIELDS:
                raise ValidationFailure(f"invalid manifest header: {manifest}")
            declared_by_group[manifest.parent] = set()
            for row in reader:
                identifier = row["id"]
                if identifier in seen:
                    raise ValidationFailure(f"duplicate language ID: {identifier}")
                for value in (identifier, row["runner"], row["root"], row["bundle"]):
                    if not re.fullmatch(r"[A-Za-z0-9._/-]+", value):
                        raise ValidationFailure(f"unsafe manifest value: {value!r}")
                seen.add(identifier)
                declared_by_group[manifest.parent].add(row["root"])
                languages.append(
                    Language(
                        identifier=identifier,
                        label=row["label"].replace("_", " "),
                        tools=row["tools"],
                        runner=row["runner"],
                        package_dir=manifest.parent / row["root"],
                        metadata=tuple(row["metadata"].split(",")),
                        api=tuple(row["api"].split(",")),
                        consumer=row["consumer"],
                        bundle=row["bundle"],
                    )
                )
    if len(languages) != 22:
        raise ValidationFailure(f"expected 22 language records, found {len(languages)}")
    for group, declared in declared_by_group.items():
        actual = {path.name for path in group.iterdir() if path.is_dir()}
        if actual != declared:
            raise ValidationFailure(
                f"package directories differ from {group / 'languages.tsv'}: "
                f"declared={sorted(declared)} actual={sorted(actual)}"
            )
    return languages


def parse_arguments(languages: list[Language]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build, install, consume, and remove standalone language packages."
    )
    parser.add_argument("--language", action="append", default=[], metavar="ID")
    parser.add_argument(
        "--allow-blocked",
        action="store_true",
        help="allow structurally verified packages whose toolchains are unavailable",
    )
    parser.add_argument(
        "--audit-only",
        action="store_true",
        help="run explicit source and bundle contract checks without runtime tests",
    )
    parser.add_argument("--timeout", type=int, default=120, metavar="SECONDS")
    parser.add_argument("--evidence", type=Path, default=DEFAULT_EVIDENCE)
    parser.add_argument("--list", action="store_true")
    args = parser.parse_args()
    if args.timeout < 1 or args.timeout > 3600:
        parser.error("--timeout must be between 1 and 3600 seconds")
    known = {language.identifier for language in languages}
    unknown = sorted(set(args.language) - known)
    if unknown:
        parser.error(f"unknown language ID: {', '.join(unknown)}")
    return args


def text(path: Path) -> str:
    if not path.is_file():
        raise ValidationFailure(f"missing required file: {path}")
    value = path.read_text(encoding="utf-8")
    if not value:
        raise ValidationFailure(f"empty required file: {path}")
    return value


def require_tokens(path: Path, *tokens: str) -> str:
    value = text(path)
    missing = [token for token in tokens if token not in value]
    if missing:
        raise ValidationFailure(f"{path}: missing contract tokens {missing}")
    return value


def require_regex(path: Path, pattern: str) -> str:
    value = text(path)
    if re.search(pattern, value, re.MULTILINE) is None:
        raise ValidationFailure(f"{path}: contract pattern did not match: {pattern}")
    return value


def require_toml(path: Path) -> dict[str, object]:
    try:
        with path.open("rb") as stream:
            return tomllib.load(stream)
    except (OSError, tomllib.TOMLDecodeError) as error:
        raise ValidationFailure(f"invalid TOML {path}: {error}") from error


def require_json(path: Path) -> dict[str, object]:
    try:
        value = json.loads(text(path))
    except json.JSONDecodeError as error:
        raise ValidationFailure(f"invalid JSON {path}: {error}") from error
    if not isinstance(value, dict):
        raise ValidationFailure(f"expected JSON object: {path}")
    return value


def validate_contract(language: Language, canonical_files: set[str]) -> str:
    root = language.package_dir
    if not root.is_dir():
        raise ValidationFailure(f"missing package directory: {root}")
    for relative in (*language.metadata, *language.api, language.consumer):
        text(root / relative)

    identifier = language.identifier
    if identifier == "haskell":
        cabal = require_tokens(
            root / "sshfling.cabal",
            "name:               sshfling",
            "version:            0.0.0",
            "data-files:",
            "runtime/sshfling.py",
            "exposed-modules:  SSHFling",
            "executable sshfling",
            "executable sshfling-consumer",
        )
        require_tokens(root / "src/SSHFling.hs", "getDataFileName", "run :: [String] -> IO Int")
        require_tokens(root / "test/Consumer.hs", "import SSHFling (run)")
    elif identifier == "ocaml":
        require_tokens(root / "dune-project", "(package", "(name sshfling)", "(dune (>= 3.11))")
        require_tokens(root / "sshfling.opam", 'version: "0.0.0"', '"dune"')
        require_tokens(
            root / "dune",
            "(install",
            "(section lib)",
            "(section libexec)",
            "runtime/sshfling.py as runtime/sshfling.py",
            "runtime/templates/.env.example",
            "runtime/templates/secrets/.gitkeep",
        )
        require_tokens(
            root / "src/dune",
            "runtime_config.ml",
            "SSHFLING_OCAML_RESOURCE_DIR",
            "(public_name sshfling)",
        )
        require_tokens(root / "src/sshfling.ml", "Runtime_config.resource_root", "Sys.file_exists runtime")
        require_tokens(root / "src/sshfling.mli", "val run : string list -> int")
        require_tokens(root / "bin/dune", "(public_name sshfling)")
    elif identifier == "common-lisp":
        require_tokens(root / "sshfling.asd", ':version "0.0.0"', ':static-file "runtime/sshfling.py"')
        require_tokens(
            root / "src/sshfling.lisp",
            '(asdf:system-source-directory "sshfling")',
            "(probe-file runtime)",
            "(defun run (arguments)",
        )
        require_tokens(root / "test/consumer.lisp", '(asdf:load-system "sshfling")', "sshfling:run")
    elif identifier == "scheme":
        require_tokens(root / "configure.ac", "AC_INIT([sshfling-guile], [0.0.0]", "AC_PROG_INSTALL")
        if "GUILE_PKG" in text(root / "configure.ac"):
            raise ValidationFailure("scheme: configure.ac still requires nonstandard GUILE_PKG")
        configure = require_tokens(root / "configure", "version=0.0.0", "Guile 3.0 is required")
        if not os.access(root / "configure", os.X_OK) or "substitute" not in configure:
            raise ValidationFailure("scheme: checked-in configure is not executable/complete")
        require_tokens(root / "Makefile.in", "install:", "uninstall:", "dist:", "build/sshfling.go")
        require_tokens(root / "module/sshfling.scm.in", '"@pkgdatadir@/runtime"', "file-exists? runtime")
        require_tokens(root / "bin/sshfling-guile.in", "@guilemoduledir@", "(run (cdr (command-line)))")
    elif identifier == "prolog":
        pack_metadata = require_tokens(root / "pack.pl", "name(sshfling).", "version('0.0.0').")
        if "requires([])." in pack_metadata:
            raise ValidationFailure("prolog: empty requires/1 is invalid SWI pack metadata")
        require_tokens(
            root / "prolog/sshfling.pl",
            ":- module(sshfling, [run/2, runtime_path/1, template_directory/1]).",
            "prolog_load_context(directory",
            "exists_file(Runtime)",
        )
        require_tokens(root / "test/consumer.pl", "sshfling:run", ":- initialization(main, main).")
    elif identifier == "smalltalk":
        try:
            tree = ET.parse(root / "package.xml")
        except ET.ParseError as error:
            raise ValidationFailure(f"smalltalk: invalid package.xml: {error}") from error
        package = tree.getroot()
        if package.findtext("name") != "SSHFling":
            raise ValidationFailure("smalltalk: package identity/file-in contract is invalid")
        declared: set[str] = set()
        package_files: set[str] = set()
        for node in package.findall("file"):
            if not node.text:
                continue
            package_files.add(node.text)
            if node.text.startswith("runtime/"):
                declared.add(node.text.removeprefix("runtime/"))
        if not {"src/SSHFling.st", "test/consumer.st"}.issubset(package_files):
            raise ValidationFailure("smalltalk: package source/test files are not declared")
        if declared != canonical_files:
            raise ValidationFailure(
                f"smalltalk: package bundle declaration differs: "
                f"missing={sorted(canonical_files - declared)} extra={sorted(declared - canonical_files)}"
            )
        require_tokens(root / "src/SSHFling.st", "SSHFling class >> run:", "SSHFLING_RUNTIME", "packageVersion")
    elif identifier == "ballerina":
        metadata = require_toml(root / "Ballerina.toml")
        package = metadata.get("package")
        if not isinstance(package, dict) or package.get("name") != "sshfling" or package.get("version") != "0.0.0":
            raise ValidationFailure("ballerina: package identity/version is invalid")
        if package.get("include") != ["resources/**", "README.md", "LICENSE"]:
            raise ValidationFailure("ballerina: BALA resources are not explicitly included")
        dependencies = require_toml(root / "Dependencies.toml")
        if dependencies.get("ballerina", {}).get("distribution-version") != "2201.12.0":
            raise ValidationFailure("ballerina: distribution lock is invalid")
        require_tokens(
            root / "sshfling.bal",
            'const string packageVersion = "0.0.0"',
            "/repositories/local/bala/grwlx/sshfling/",
            "public type RunResult record",
            "file:test(path, file:EXISTS)",
            "public function runAndCapture(string[] args) returns RunResult",
            "public function run(string[] args) returns int",
        )
    elif identifier == "roc":
        require_tokens(root / "package.roc", "package [SSHFling] {}")
        require_tokens(
            root / "SSHFling.roc",
            "module [run!, runtime_path!, template_directory!, package_version]",
            'package_version = "0.0.0"',
            "File.exists!(runtime)?",
            "Cmd.exec_exit_code!()",
        )
        main = require_tokens(
            root / "main.roc",
            'sshfling: "package.roc"',
            "import sshfling.SSHFling",
            "List.drop_first(raw_args, 1)",
            'Err(Exit(status, ""))',
            "SSHFling.run!",
        )
        consumer = require_tokens(root / "test/consumer.roc", 'sshfling: "../package.roc"', "import sshfling.SSHFling")
        if 'Cmd.exec!("roc"' in main + consumer:
            raise ValidationFailure("roc: consumer recursively invokes roc instead of importing package")
    elif identifier == "janet":
        require_tokens(root / "project.janet", ':name "sshfling"', ':version "0.0.0"', ':files @[')
        api = require_tokens(
            root / "src/sshfling/init.janet",
            "module/expand-path (dyn :current-file)",
            'configured-or "SSHFLING_PACKAGE_ROOT" package-root',
            "(os/stat (runtime-path))",
        )
        if '(os/cwd)' in api:
            raise ValidationFailure("janet: default resource lookup still depends on CWD")
        require_tokens(root / "bin/sshfling", "import sshfling", "sshfling/run")
    elif identifier == "ring":
        require_tokens(
            root / "package.ring",
            ':version = "0.0.0"',
            ':files = ["lib.ring"',
            '"bin"',
        )
        api = require_tokens(
            root / "lib.ring",
            "sysget(cName)",
            "func pathdirectory cPath",
            "fexists(runtimepath())",
            "SSHFLING_TEMPLATE_DIR",
            "func normalizedstatus nStatus",
            "func run aArgs",
        )
        if "cValue = get(cName)" in api:
            raise ValidationFailure("ring: environment lookup still uses variable get()")
        launcher = require_tokens(
            root / "bin/sshfling-ring",
            "SSHFLING_RING_STATUS_FILE",
            "SSHFLING_PACKAGE_ROOT",
            "exec ring main.ring",
        )
        if not os.access(root / "bin/sshfling-ring", os.X_OK) or "exit \"$status\"" not in launcher:
            raise ValidationFailure("ring: POSIX status wrapper is not executable/complete")
    elif identifier == "raku":
        metadata = require_json(root / "META6.json")
        if (
            metadata.get("name") != "SSHFling"
            or metadata.get("version") != "0.0.0"
            or metadata.get("provides", {}).get("SSHFling") != "lib/SSHFling.rakumod"
            or "runtime" not in metadata.get("resources", [])
        ):
            raise ValidationFailure("raku: package identity/assets contract is invalid")
        api = require_tokens(
            root / "lib/SSHFling.rakumod",
            "unit module SSHFling",
            "sub package-version",
            "sub runtime-path",
            "sub template-directory",
            "sub run(@arguments --> Int) is export",
            "Proc::Async.new($python, $runtime, |@arguments)",
            "return 127 unless $runtime.IO.f",
        )
        if "shell " in api or "run @arguments" in api:
            raise ValidationFailure("raku: package must use argv-array process execution")
        require_tokens(root / "bin/sshfling-raku", "use SSHFling", "exit run(@*ARGS)")
        require_tokens(root / "test/consumer.raku", "use SSHFling", "exit run(@*ARGS)")
    elif identifier == "haxe":
        metadata = require_json(root / "haxelib.json")
        if (
            metadata.get("name") != "sshfling"
            or metadata.get("version") != "0.0.0"
            or metadata.get("classPath") != "src"
            or "ssh" not in metadata.get("tags", [])
        ):
            raise ValidationFailure("haxe: package identity/classPath contract is invalid")
        require_tokens(root / "build.hxml", "-cp src", "-main Main", "-neko bin/sshfling-haxe.n")
        api = require_tokens(
            root / "src/sshfling/SSHFling.hx",
            "class SSHFling",
            'packageVersion:String = "0.0.0"',
            "PackageRootMacro.sourcePackageRoot()",
            "public static function runtimePath():String",
            "public static function templateDirectory():String",
            "public static function run(arguments:Array<String>):Int",
            "Sys.command(command, commandArguments)",
            "return 127",
        )
        if "Sys.command(command + " in api:
            raise ValidationFailure("haxe: package must use argv-array process execution")
        require_tokens(
            root / "src/sshfling/PackageRootMacro.hx",
            "public static macro function sourcePackageRoot()",
            "Context.getPosInfos",
            "sys.FileSystem.fullPath",
        )
        require_tokens(root / "src/Main.hx", "import sshfling.SSHFling", "SSHFling.run(Sys.args())")
        require_tokens(root / "test/Consumer.hx", "import sshfling.SSHFling", "SSHFling.run(Sys.args())")
    elif identifier == "apl":
        metadata = require_json(root / "apl-package.json")
        if (
            metadata.get("version") != "0.0.0"
            or metadata.get("interpreter") != "GNU APL"
            or metadata.get("source") != "src/sshfling.apl"
            or "runtime" not in metadata.get("assets", [])
        ):
            raise ValidationFailure("apl: package version/assets contract is invalid")
        require_tokens(
            root / "src/sshfling.apl",
            "SSHFling∆PackageVersion",
            "SSHFling∆Run",
            "SSHFLING_RUNTIME",
            "SSHFLING_TEMPLATE_DIR",
            "⎕FIO[24]",
            "SSHFling∆ApplicationArgs",
            "SSHFling∆WriteStatus",
        )
        require_tokens(
            root / "test/consumer.apl",
            "SSHFling∆Run",
            "SSHFling∆ApplicationArgs",
            "SSHFling∆WriteStatus",
        )
    elif identifier == "j":
        require_tokens(root / "manifest.ijs", "VERSION=: '0.0.0'", "runtime/", "src/sshfling.ijs")
        api = require_tokens(root / "src/sshfling.ijs", "run=: 3 : 0", "jpath '~addons/sshfling'")
        if "configuredor jpath '.'" in api:
            raise ValidationFailure("j: default resource lookup still depends on CWD")
        require_tokens(root / "test/consumer.ijs", "load 'src/sshfling.ijs'", "run_sshfling_")
        require_tokens(root / "bin/sshfling.ijs", "SSHFLING_PACKAGE_ROOT", "run_sshfling_ 2}.ARGV")
    elif identifier == "julia":
        metadata = require_toml(root / "Project.toml")
        if metadata.get("name") != "SSHFling" or metadata.get("version") != "0.0.0":
            raise ValidationFailure("julia: Project.toml package identity is invalid")
        require_tokens(root / "src/SSHFling.jl", "export run", "@__DIR__", "return 127")
        require_tokens(root / "test/runtests.jl", "using SSHFling", "SSHFling.run")
        require_tokens(root / "bin/sshfling.jl", "using SSHFling", "SSHFling.run(ARGS)")
    elif identifier == "matlab":
        metadata = require_json(root / "matlab-package.json")
        if (
            metadata.get("version") != "0.0.0"
            or metadata.get("interpreter") != "GNU Octave"
            or metadata.get("mathworks_matlab_runtime") != "not claimed"
            or "runtime" not in metadata.get("assets", [])
        ):
            raise ValidationFailure("matlab: package version/runtime contract is invalid")
        require_tokens(root / "+sshfling/packageVersion.m", "function version = packageVersion()", "0.0.0")
        require_tokens(root / "+sshfling/runtimePath.m", "SSHFLING_PACKAGE_ROOT", "SSHFLING_RUNTIME")
        require_tokens(root / "+sshfling/templateDirectory.m", "SSHFLING_TEMPLATE_DIR")
        require_tokens(
            root / "+sshfling/run.m",
            "function status = run(arguments)",
            "sshfling.runtimePath()",
            "shellQuote",
            "system(command)",
            "status = 127",
        )
        require_tokens(root / "test/consumer.m", "argv()", "sshfling.run(args)", "exit(status)")
    elif identifier == "wolfram-language":
        metadata = require_json(root / "mathics-package.json")
        if (
            metadata.get("version") != "0.0.0"
            or metadata.get("interpreter") != "Mathics3"
            or metadata.get("wolfram_engine_runtime") != "not claimed"
            or metadata.get("source") != "src/SSHFling.wl"
            or metadata.get("wrapper") != "bin/sshfling-mathics-runner"
            or "runtime" not in metadata.get("assets", [])
        ):
            raise ValidationFailure("wolfram-language: package version/runtime contract is invalid")
        api = require_tokens(
            root / "src/SSHFling.wl",
            "BeginPackage[\"SSHFling`\"]",
            "RunSSHFling[arguments_List]",
            "ToCharacterCode[value, \"UTF8\"]",
            "SSHFLING_MATHICS_ARG_FILE",
            "SetEnvironment",
            "Run[wrapper]",
        )
        if "RunProcess" in api:
            raise ValidationFailure("wolfram-language: Mathics package must not claim RunProcess support")
        runner = require_tokens(
            root / "bin/sshfling-mathics-runner",
            "binascii.unhexlify",
            "subprocess.call([sys.executable, runtime, *arguments]",
            "raise SystemExit(127)",
        )
        if not os.access(root / "bin/sshfling-mathics-runner", os.X_OK) or "shell=True" in runner:
            raise ValidationFailure("wolfram-language: runner wrapper is not executable or uses shell execution")
        require_tokens(root / "test/consumer.wl", "Get[FileNameJoin", "SSHFling`RunSSHFling", "Rest[$ScriptCommandLine]")
    elif identifier == "r":
        description = require_tokens(
            root / "DESCRIPTION",
            "Package: sshfling",
            "Version: 0.0.0",
            "Depends: R (>= 4.3.0)",
            "Suggests: testthat",
        )
        if "License: file LICENSE" not in description:
            raise ValidationFailure("r: package license metadata is absent")
        require_tokens(root / "NAMESPACE", "export(run)", "export(runtime_path)", "export(template_directory)")
        require_tokens(root / "R/sshfling.R", 'system.file("runtime", "sshfling.py"', "file.exists(runtime)", "127L")
        require_tokens(root / "man/sshfling.Rd", "\\alias{run}", "\\alias{runtime_path}", "\\arguments")
        require_tokens(root / "tests/check-api.R", "--definitely-invalid", "127L")
        require_tokens(root / "tests/testthat/test-api.R", "testthat::test_that", "testthat::expect_identical")
    elif identifier == "q":
        metadata = require_json(root / "manifest.yaml")
        if metadata.get("name") != "sshfling" or metadata.get("version") != "0.0.0":
            raise ValidationFailure("q: manifest identity/version is invalid")
        api = require_tokens(root / "src/sshfling.q", ".sshfling.run:", ".sshfling.sourceFile:string .z.f")
        if 'configuredOr["SSHFLING_PACKAGE_ROOT";"."]' in api:
            raise ValidationFailure("q: default resource lookup still depends on CWD")
        require_tokens(root / "init.q", "\\l src/sshfling.q")
    elif identifier == "erlang":
        require_tokens(root / "rebar.config", "warnings_as_errors", '{deps, []}')
        require_tokens(root / "src/sshfling.app.src", "{vsn, \"0.0.0\"}", "{modules, [sshfling]}")
        require_tokens(root / "src/sshfling.erl", "code:priv_dir(sshfling)", "filelib:is_regular(Runtime)", "run(Arguments)")
        require_tokens(root / "test/sshfling_consumer.erl", "sshfling:run")
    elif identifier == "elixir":
        require_tokens(root / "mix.exs", 'version: "0.0.0"', 'files: ["lib", "priv/runtime"', "deps: []")
        require_tokens(root / "lib/sshfling.ex", "Application.app_dir(:sshfling", "File.regular?(runtime)", "def run(arguments)")
        require_tokens(root / "test/sshfling_consumer_test.exs", "SSHFling.run")
    elif identifier == "gleam":
        metadata = require_toml(root / "gleam.toml")
        if metadata.get("name") != "sshfling" or metadata.get("version") != "0.0.0" or metadata.get("target") != "erlang":
            raise ValidationFailure("gleam: package identity/version/target is invalid")
        require_tokens(root / "src/sshfling.gleam", '@external(erlang, "sshfling_ffi", "run")', "pub fn run")
        ffi = require_tokens(root / "src/sshfling_ffi.erl", "code:priv_dir(sshfling)", "filelib:is_regular(Runtime)")
        if 'filename:absname(".")' in ffi:
            raise ValidationFailure("gleam: default resource lookup still depends on CWD")
        require_tokens(root / "test/consumer.gleam", "import sshfling", "sshfling.run")
    else:
        raise ValidationFailure(f"no explicit source contract for {identifier}")

    return f"ecosystem={identifier};metadata=parsed;api=explicit;consumer=explicit"


def copy_entry(source: Path, destination: Path) -> None:
    if source.is_dir():
        shutil.copytree(source, destination, copy_function=shutil.copy2)
    else:
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)


def create_canonical_bundle(root: Path) -> tuple[Path, str, list[str]]:
    constants = source_constants(REPO_ROOT / "bin/sshfling")
    version = constants.get("VERSION")
    entries = constants.get("TEMPLATE_ENTRIES")
    if version != EXPECTED_VERSION:
        raise ValidationFailure(
            f"canonical runtime version must be {EXPECTED_VERSION}, found {version!r}"
        )
    requested = os.environ.get("SSHFLING_VERSION")
    if requested is not None and requested != version:
        raise ValidationFailure(
            f"SSHFLING_VERSION={requested!r} does not equal canonical {version!r}"
        )
    if not isinstance(entries, list) or not entries or not all(isinstance(item, str) for item in entries):
        raise ValidationFailure("canonical TEMPLATE_ENTRIES is invalid")
    bundle = root / "canonical-runtime"
    templates = bundle / "templates"
    templates.mkdir(parents=True)
    shutil.copy2(REPO_ROOT / "bin/sshfling", bundle / "sshfling.py")
    (bundle / "sshfling.py").chmod(0o755)
    for relative in entries:
        copy_entry(REPO_ROOT / relative, templates / relative)
    compile((bundle / "sshfling.py").read_bytes(), "sshfling.py", "exec")
    return bundle, version, entries


def file_digest(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def file_inventory(root: Path) -> dict[str, tuple[str, int]]:
    return {
        path.relative_to(root).as_posix(): (file_digest(path), path.stat().st_mode & 0o777)
        for path in sorted(root.rglob("*"))
        if path.is_file()
    }


def inject_version(stage: Path, version: str, bundle: Path) -> int:
    changed = 0
    for path in stage.rglob("*"):
        if not path.is_file():
            continue
        if bundle == path or bundle in path.parents:
            continue
        try:
            value = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        if "0.0.0" in value:
            path.write_text(value.replace("0.0.0", version), encoding="utf-8")
            changed += 1
    if not changed:
        raise ValidationFailure("staged package contains no injectable 0.0.0 version")
    return changed


def stage_language(
    root: Path,
    language: Language,
    canonical: Path,
    version: str,
) -> tuple[Path, Path]:
    language_root = root / language.identifier
    stage = language_root / "stage"
    work = language_root / "work"
    shutil.copytree(
        language.package_dir,
        stage,
        copy_function=shutil.copy2,
        ignore=shutil.ignore_patterns(*SOURCE_IGNORES),
    )
    work.mkdir(parents=True)
    shutil.copy2(REPO_ROOT / "LICENSE", stage / "LICENSE")
    shutil.copy2(REPO_ROOT / "README.md", stage / "README.md")
    bundle = stage / language.bundle
    bundle.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(canonical, bundle, copy_function=shutil.copy2)
    inject_version(stage, version, bundle)
    expected = file_inventory(canonical)
    actual = file_inventory(bundle)
    if actual != expected:
        raise ValidationFailure(f"{language.identifier}: staged canonical bundle differs")
    return stage, work


def isolated_environment(work: Path, extra: dict[str, str] | None = None) -> dict[str, str]:
    home = work / "home"
    cache = work / "cache"
    config = work / "config"
    data = work / "data"
    state = work / "state"
    temporary = work / "tmp"
    for directory in (home, cache, config, data, state, temporary):
        directory.mkdir(parents=True, exist_ok=True)
    environment = os.environ.copy()
    for name in UNSET_RUNTIME_ENV:
        environment.pop(name, None)
    environment.update(
        {
            "HOME": str(home),
            "XDG_CACHE_HOME": str(cache),
            "XDG_CONFIG_HOME": str(config),
            "XDG_DATA_HOME": str(data),
            "XDG_STATE_HOME": str(state),
            "TMPDIR": str(temporary),
            "PYTHONDONTWRITEBYTECODE": "1",
            "PYTHONUNBUFFERED": "1",
            "LC_ALL": "C.UTF-8",
            "LANG": "C.UTF-8",
        }
    )
    if extra:
        environment.update({key: str(value) for key, value in extra.items()})
    return environment


def safe_extract(archive: tarfile.TarFile, destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    base = destination.resolve()
    for member in archive.getmembers():
        target = (destination / member.name).resolve()
        if base != target and base not in target.parents:
            raise ValidationFailure(f"archive has unsafe member: {member.name}")
        if member.issym() or member.islnk():
            raise ValidationFailure(f"archive has unsupported link: {member.name}")
    archive.extractall(destination)


def archive_tree(source: Path, archive: Path, root_name: str) -> None:
    """Write a byte-reproducible source archive with normalized ownership and times."""
    archive.parent.mkdir(parents=True, exist_ok=True)
    temporary = archive.with_name(f".{archive.name}.{os.getpid()}.tmp")
    try:
        with temporary.open("wb") as raw:
            with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as compressed:
                with tarfile.open(fileobj=compressed, mode="w", format=tarfile.PAX_FORMAT) as stream:
                    paths = [source, *sorted(source.rglob("*"), key=lambda item: item.relative_to(source).as_posix())]
                    for path in paths:
                        if path.is_symlink():
                            raise ValidationFailure(f"source archive contains unsupported link: {path}")
                        relative = path.relative_to(source).as_posix() if path != source else ""
                        member_name = root_name if not relative else f"{root_name}/{relative}"
                        info = stream.gettarinfo(str(path), arcname=member_name)
                        info.uid = 0
                        info.gid = 0
                        info.uname = ""
                        info.gname = ""
                        info.mtime = 0
                        if path.is_file():
                            with path.open("rb") as payload:
                                stream.addfile(info, payload)
                        else:
                            stream.addfile(info)
            raw.flush()
            os.fsync(raw.fileno())
        os.replace(temporary, archive)
    finally:
        temporary.unlink(missing_ok=True)


def extract_single_root(archive: Path, destination: Path) -> Path:
    with tarfile.open(archive, "r:*") as stream:
        safe_extract(stream, destination)
    children = [path for path in destination.iterdir()]
    if len(children) != 1 or not children[0].is_dir():
        raise ValidationFailure(f"archive does not contain one package root: {archive}")
    return children[0]


def publish_source_archive(
    stage: Path,
    language: Language,
    version: str,
    verification_root: Path,
    evidence: Evidence,
) -> Path:
    root_name = f"sshfling-{language.identifier}-{version}"
    archive = DIST_ROOT / f"{root_name}.tar.gz"
    archive_tree(stage, archive, root_name)
    digest = file_digest(archive)
    evidence.record(
        language.identifier,
        "PASS",
        "published-source-archive",
        status=0,
        detail=f"archive={archive};bytes={archive.stat().st_size};sha256={digest}",
    )

    reproduction = verification_root / f"{root_name}.reproduced.tar.gz"
    archive_tree(stage, reproduction, root_name)
    reproduced_digest = file_digest(reproduction)
    if reproduced_digest != digest:
        raise ValidationFailure(
            f"{language.identifier}: deterministic source archive hash mismatch: "
            f"{digest} != {reproduced_digest}"
        )
    reproduction.unlink()

    extracted = extract_single_root(archive, verification_root / "published-source")
    expected = file_inventory(stage)
    actual = file_inventory(extracted)
    if actual != expected:
        missing = sorted(set(expected) - set(actual))
        extra = sorted(set(actual) - set(expected))
        changed = sorted(name for name in set(expected) & set(actual) if expected[name] != actual[name])
        raise ValidationFailure(
            f"{language.identifier}: published archive inventory mismatch: "
            f"missing={missing};extra={extra};changed={changed}"
        )
    evidence.record(
        language.identifier,
        "PASS",
        "published-source-inventory",
        status=0,
        detail=f"files={len(actual)};inventory_match=True;reproducible_sha256={digest}",
    )
    shutil.rmtree(extracted.parent)
    return archive


def prolog_atom(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


class PackageRunner:
    def __init__(
        self,
        language: Language,
        stage: Path,
        work: Path,
        canonical: Path,
        version: str,
        entries: list[str],
        evidence: Evidence,
        timeout: int,
        tools: dict[str, str],
        published_archive: Path,
    ):
        self.language = language
        self.stage = stage
        self.work = work
        self.canonical = canonical
        self.version = version
        self.entries = entries
        self.evidence = evidence
        self.timeout = timeout
        self.tools = tools
        self.published_archive = published_archive
        self.command_count = 0
        self.base_env = isolated_environment(work)
        self.evidence.record(
            language.identifier,
            "INFO",
            "isolated-environment",
            detail="unset=" + ",".join(UNSET_RUNTIME_ENV) + f";HOME={self.base_env['HOME']}",
        )

    def command(
        self,
        phase: str,
        arguments: list[str | Path],
        *,
        cwd: Path | None = None,
        env: dict[str, str] | None = None,
        expected: set[int] | Callable[[int], bool] = {0},
    ) -> subprocess.CompletedProcess[str]:
        argv = [str(argument) for argument in arguments]
        command_text = shlex.join(argv)
        run_cwd = (cwd or self.stage).resolve()
        run_env = self.base_env.copy()
        if env:
            run_env.update({key: str(value) for key, value in env.items()})
        self.command_count += 1
        print(f"COMMAND\t{self.language.identifier}\t{phase}\t{command_text}", flush=True)
        try:
            completed = subprocess.run(
                argv,
                cwd=run_cwd,
                env=run_env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=self.timeout,
                check=False,
            )
        except subprocess.TimeoutExpired as error:
            stdout = error.stdout or ""
            stderr = error.stderr or ""
            if isinstance(stdout, bytes):
                stdout = stdout.decode("utf-8", "replace")
            if isinstance(stderr, bytes):
                stderr = stderr.decode("utf-8", "replace")
            self.evidence.record(
                self.language.identifier,
                "TIMEOUT",
                phase,
                status="timeout",
                cwd=run_cwd,
                command=command_text,
                stdout=stdout,
                stderr=stderr,
                detail=f"timeout_seconds={self.timeout}",
            )
            raise ValidationFailure(f"{self.language.identifier}: {phase} timed out") from error
        accepted = expected(completed.returncode) if callable(expected) else completed.returncode in expected
        self.evidence.record(
            self.language.identifier,
            "PASS" if accepted else "FAIL",
            phase,
            status=completed.returncode,
            cwd=run_cwd,
            command=command_text,
            stdout=completed.stdout,
            stderr=completed.stderr,
        )
        if not accepted:
            print(completed.stdout, end="", file=sys.stderr)
            print(completed.stderr, end="", file=sys.stderr)
            raise ValidationFailure(
                f"{self.language.identifier}: {phase} returned {completed.returncode}"
            )
        return completed

    def check(self, phase: str, condition: bool, detail: str) -> None:
        self.evidence.record(
            self.language.identifier,
            "PASS" if condition else "FAIL",
            phase,
            status=0 if condition else 1,
            detail=detail,
        )
        if not condition:
            raise ValidationFailure(f"{self.language.identifier}: {phase}: {detail}")

    def record_archive(self, phase: str, archive: Path) -> None:
        self.check(
            phase,
            archive.is_file() and archive.stat().st_size > 0,
            f"archive={archive.name};bytes={archive.stat().st_size if archive.exists() else 0};"
            f"sha256={file_digest(archive) if archive.exists() else 'missing'}",
        )

    def source_archive(self, package_name: str | None = None) -> Path:
        if package_name is None:
            self.record_archive("source-archive", self.published_archive)
            return self.published_archive
        root_name = package_name
        archive = self.work / f"{root_name}.tar.gz"
        archive_tree(self.stage, archive, root_name)
        self.record_archive("source-archive", archive)
        return archive

    def verify_runtime(self, installed_runtime: Path, phase: str = "installed-resources") -> None:
        expected = file_inventory(self.canonical)
        actual = file_inventory(installed_runtime) if installed_runtime.is_dir() else {}
        files_match = set(actual) == set(expected)
        digests_match = files_match and all(actual[name][0] == expected[name][0] for name in expected)
        executables_match = files_match and all(
            bool(actual[name][1] & 0o111) == bool(expected[name][1] & 0o111)
            for name in expected
        )
        mode_mismatches = (
            [
                f"{name}:{expected[name][1]:03o}->{actual[name][1]:03o}"
                for name in expected
                if name in actual
                and bool(actual[name][1] & 0o111) != bool(expected[name][1] & 0o111)
            ]
            if files_match
            else []
        )
        self.check(
            phase,
            files_match and digests_match and executables_match,
            f"root={installed_runtime};files={len(actual)};files_match={files_match};"
            f"digests_match={digests_match};executable_modes_match={executables_match};"
            f"mode_mismatches={','.join(mode_mismatches) or 'none'}",
        )

    def verify_init(self, smoke: Path) -> None:
        expected_templates = file_inventory(self.canonical / "templates")
        failures: list[str] = []
        for name, (digest, mode) in expected_templates.items():
            installed = smoke / name
            if not installed.is_file():
                failures.append(f"missing:{name}")
                continue
            if file_digest(installed) != digest:
                failures.append(f"digest:{name}")
            if bool(installed.stat().st_mode & 0o111) != bool(mode & 0o111):
                failures.append(f"mode:{name}")
        environment = smoke / ".env"
        if not environment.is_file() or environment.stat().st_mode & 0o777 != 0o600:
            failures.append("mode:.env")
        self.check(
            "init-assets",
            not failures,
            f"smoke={smoke};templates={len(expected_templates)};failures={','.join(failures) or 'none'}",
        )

    def assert_version_output(self, completed: subprocess.CompletedProcess[str]) -> None:
        expected = f"sshfling {self.version}"
        self.check(
            "exact-version-output",
            completed.stdout == f"{expected}\n",
            f"expected={expected};actual={completed.stdout.removesuffix(chr(10))}",
        )

    def run_status_cases(
        self,
        command_factory: Callable[[list[str]], list[str | Path]],
        *,
        cwd: Path,
        env: dict[str, str] | None = None,
        smoke: Path | None = None,
    ) -> None:
        version = self.command("consumer-version", command_factory(["--version"]), cwd=cwd, env=env)
        self.assert_version_output(version)
        self.command(
            "consumer-invalid-option",
            command_factory(["--definitely-invalid"]),
            cwd=cwd,
            env=env,
            expected={2},
        )
        smoke = smoke or self.work / "smoke"
        self.command(
            "consumer-init",
            command_factory(["init", str(smoke), "--force", "--session-seconds", "60"]),
            cwd=cwd,
            env=env,
        )
        self.verify_init(smoke)
        missing_env = dict(env or {})
        missing_env["SSHFLING_RUNTIME"] = str(self.work / "missing-runtime.py")
        self.command(
            "consumer-missing-runtime",
            command_factory([]),
            cwd=cwd,
            env=missing_env,
            expected={127},
        )

    def run(self) -> None:
        method = getattr(self, f"validate_{self.language.runner}", None)
        if method is None:
            raise ValidationFailure(
                f"{self.language.identifier}: native package validation is not implemented"
            )
        method()

    def probe(self, phase: str, arguments: list[str]) -> None:
        self.command(f"tool-{phase}", arguments, cwd=self.work)

    def validate_ocaml(self) -> None:
        self.probe("ocamlc-version", [self.tools["ocamlc"], "-version"])
        self.probe("dune-version", [self.tools["dune"], "--version"])
        archive = self.source_archive()
        source = extract_single_root(archive, self.work / "source")
        prefix = self.work / "prefix"
        resource_root = prefix / "lib/sshfling/runtime"
        build_env = {
            "DUNE_CACHE": "disabled",
            "SSHFLING_OCAML_RESOURCE_DIR": str(resource_root),
        }
        self.command(
            "dune-build-install-artifacts",
            [self.tools["dune"], "build", f"--root={source}", "--display=short", "@install"],
            cwd=self.work,
            env=build_env,
        )
        self.command(
            "dune-install",
            [self.tools["dune"], "install", f"--root={source}", f"--prefix={prefix}", "sshfling"],
            cwd=self.work,
            env=build_env,
        )
        self.verify_runtime(resource_root)
        cli = prefix / "bin/sshfling"
        cli_result = self.command("installed-cli-version", [cli, "--version"], cwd=self.work)
        self.assert_version_output(cli_result)
        consumer = self.work / "external-ocaml-consumer"
        consumer.mkdir()
        (consumer / "dune-project").write_text("(lang dune 3.11)\n(name external_consumer)\n", encoding="utf-8")
        (consumer / "dune").write_text("(executable (name main) (libraries sshfling))\n", encoding="utf-8")
        (consumer / "main.ml").write_text(
            "let () = exit (Sshfling.run (Array.to_list Sys.argv |> List.tl))\n",
            encoding="utf-8",
        )
        consumer_env = {"DUNE_CACHE": "disabled", "OCAMLPATH": str(prefix / "lib")}
        self.command("external-consumer-build", [self.tools["dune"], "build"], cwd=consumer, env=consumer_env)
        executable = consumer / "_build/default/main.exe"
        unrelated = self.work / "unrelated-cwd"
        unrelated.mkdir()
        self.run_status_cases(lambda args: [executable, *args], cwd=unrelated, env=consumer_env)
        self.command(
            "dune-uninstall",
            [self.tools["dune"], "uninstall", f"--root={source}", f"--prefix={prefix}", "sshfling"],
            cwd=self.work,
            env=build_env,
        )
        shutil.rmtree(consumer / "_build", ignore_errors=True)
        self.check("cli-removed", not cli.exists(), f"path={cli}")
        self.command(
            "import-absence",
            [self.tools["dune"], "build"],
            cwd=consumer,
            env=consumer_env,
            expected=lambda status: status != 0,
        )

    def validate_haskell(self) -> None:
        self.probe("ghc-version", [self.tools["ghc"], "--version"])
        self.probe("cabal-version", [self.tools["cabal"], "--version"])
        self.source_archive()
        sdist_dir = self.work / "cabal-sdist"
        sdist_dir.mkdir()
        self.command(
            "cabal-native-sdist",
            [self.tools["cabal"], "sdist", f"--output-directory={sdist_dir}"],
            cwd=self.stage,
        )
        native_archives = list(sdist_dir.glob(f"sshfling-{self.version}.tar.gz"))
        self.check("cabal-sdist-count", len(native_archives) == 1, f"archives={native_archives}")
        self.record_archive("cabal-sdist-archive", native_archives[0])
        source = extract_single_root(native_archives[0], self.work / "installed-source")

        package_env = self.work / "haskell-package.env"
        prefix = self.work / "prefix"
        bin_dir = prefix / "bin"
        bin_dir.mkdir(parents=True)
        self.command(
            "cabal-library-install",
            [
                self.tools["cabal"],
                "install",
                "--offline",
                "--lib",
                "lib:sshfling",
                f"--package-env={package_env}",
            ],
            cwd=source,
        )
        self.command(
            "cabal-cli-install",
            [
                self.tools["cabal"],
                "install",
                "--offline",
                "exe:sshfling",
                "--install-method=copy",
                "--overwrite-policy=always",
                f"--installdir={bin_dir}",
            ],
            cwd=source,
        )
        cli = bin_dir / "sshfling"
        cli_result = self.command("installed-cli-version", [cli, "--version"], cwd=self.work)
        self.assert_version_output(cli_result)

        consumer_dir = self.work / "external-haskell-consumer"
        consumer_dir.mkdir()
        consumer_source = consumer_dir / "Main.hs"
        consumer_source.write_text(
            "module Main (main) where\n\n"
            "import SSHFling (run, runtimePath)\n"
            "import System.Environment (getArgs, lookupEnv)\n"
            "import System.Exit (ExitCode (..), exitWith)\n\n"
            "main :: IO ()\n"
            "main = do\n"
            "  inspect <- lookupEnv \"SSHFLING_HASKELL_PRINT_RUNTIME\"\n"
            "  case inspect of\n"
            "    Just \"1\" -> runtimePath >>= putStrLn\n"
            "    _ -> do\n"
            "      status <- getArgs >>= run\n"
            "      exitWith $ if status == 0 then ExitSuccess else ExitFailure status\n",
            encoding="utf-8",
        )
        self.command(
            "external-consumer-build",
            [
                self.tools["ghc"],
                f"-package-env={package_env}",
                "-Wall",
                "-Werror",
                consumer_source,
                "-o",
                consumer_dir / "sshfling-consumer",
            ],
            cwd=consumer_dir,
        )
        consumer = consumer_dir / "sshfling-consumer"
        runtime_result = self.command(
            "installed-runtime-path",
            [consumer],
            cwd=self.work,
            env={"SSHFLING_HASKELL_PRINT_RUNTIME": "1"},
        )
        installed_runtime_file = Path(runtime_result.stdout.strip())
        self.verify_runtime(installed_runtime_file.parent)
        unrelated = self.work / "unrelated-cwd"
        unrelated.mkdir()
        self.run_status_cases(lambda args: [consumer, *args], cwd=unrelated)

        shutil.rmtree(prefix)
        package_env.unlink()
        shutil.rmtree(self.work / "home", ignore_errors=True)
        shutil.rmtree(self.work / "state", ignore_errors=True)
        shutil.rmtree(source)
        self.check("cli-removed", not cli.exists(), f"path={cli}")
        self.command(
            "import-absence",
            [
                self.tools["ghc"],
                f"-package-env={package_env}",
                "-fno-code",
                consumer_source,
            ],
            cwd=consumer_dir,
            expected=lambda status: status != 0,
        )
        self.check("package-removed", not installed_runtime_file.exists(), f"path={installed_runtime_file}")

    def validate_julia(self) -> None:
        self.probe("julia-version", [self.tools["julia"], "--version"])
        archive = self.source_archive()
        source = extract_single_root(archive, self.work / "installed-source")
        depot = self.work / "julia-depot"
        consumer = self.work / "external-julia-consumer"
        consumer.mkdir()
        consumer_script = consumer / "consumer.jl"
        consumer_script.write_text(
            "using SSHFling\nexit(SSHFling.run(ARGS))\n",
            encoding="utf-8",
        )
        env = {
            "JULIA_DEPOT_PATH": str(depot),
            "JULIA_PKG_OFFLINE": "true",
            "JULIA_HISTORY": str(self.work / "julia-history"),
        }
        julia = [self.tools["julia"], "--startup-file=no", f"--project={consumer}"]
        self.command(
            "julia-package-install",
            [
                *julia,
                "-e",
                "using Pkg; Pkg.develop(path=ARGS[1]); Pkg.precompile()",
                source,
            ],
            cwd=consumer,
            env=env,
        )
        self.command(
            "julia-package-test",
            [
                self.tools["julia"],
                "--startup-file=no",
                f"--project={source}",
                "-e",
                "using Pkg; Pkg.test()",
            ],
            cwd=source,
            env=env,
        )
        self.verify_runtime(source / "runtime")
        unrelated = self.work / "unrelated-cwd"
        unrelated.mkdir()
        command = lambda args: [
            *julia,
            "-e",
            "script = popfirst!(ARGS); include(script)",
            "--",
            consumer_script,
            *args,
        ]
        self.run_status_cases(command, cwd=unrelated, env=env)
        cli_result = self.command(
            "installed-cli-version",
            [
                *julia,
                "-e",
                "script = popfirst!(ARGS); include(script)",
                "--",
                source / "bin/sshfling.jl",
                "--version",
            ],
            cwd=unrelated,
            env=env,
        )
        self.assert_version_output(cli_result)
        self.command(
            "julia-package-remove",
            [*julia, "-e", 'using Pkg; Pkg.rm("SSHFling")'],
            cwd=consumer,
            env=env,
        )
        shutil.rmtree(source)
        self.command(
            "import-absence",
            [*julia, "-e", "using SSHFling"],
            cwd=unrelated,
            env=env,
            expected=lambda status: status != 0,
        )
        self.check("package-removed", not source.exists(), f"path={source}")

    def validate_matlab(self) -> None:
        self.probe("octave-version", [self.tools["octave-cli"], "--version"])
        archive = self.source_archive()
        source = extract_single_root(archive, self.work / "source")
        self.verify_runtime(source / "runtime")
        env = {
            "SSHFLING_PACKAGE_ROOT": str(source),
            "OCTAVE_HISTFILE": str(self.work / "octave-history"),
        }
        octave = [
            self.tools["octave-cli"],
            "--quiet",
            "--no-gui",
            "--no-init-file",
            "--path",
            str(source),
        ]
        unrelated = self.work / "unrelated-cwd"
        unrelated.mkdir()

        consumer = self.work / "external-consumer.m"
        consumer.write_text(
            "args = argv();\n"
            "if ~isempty(args) && strcmp(args{1}, '--')\n"
            "    args = args(2:end);\n"
            "end\n"
            "status = sshfling.run(args);\n"
            "exit(status);\n",
            encoding="utf-8",
        )
        command = lambda args: [*octave, consumer, "--", *args]
        self.run_status_cases(command, cwd=unrelated, env=env)

        packaged_version = self.command(
            "packaged-consumer-version",
            [*octave, source / "test/consumer.m", "--", "--version"],
            cwd=unrelated,
            env=env,
        )
        self.assert_version_output(packaged_version)

        shutil.rmtree(source)
        self.check("package-removed", not source.exists(), f"path={source}")
        self.command(
            "import-absence",
            [*octave, consumer, "--", "--version"],
            cwd=unrelated,
            env=env,
            expected=lambda status: status != 0,
        )

    def validate_wolfram_language(self) -> None:
        self.probe("mathics-version", [self.tools["mathics"], "--version"])
        archive = self.source_archive()
        source = extract_single_root(archive, self.work / "source with spaces")
        self.verify_runtime(source / "runtime")
        env = {
            "SSHFLING_PACKAGE_ROOT": str(source),
            "MATHICS3_HISTFILE": str(self.work / "mathics-history"),
        }
        mathics = [self.tools["mathics"], "--quiet", "--file"]
        unrelated = self.work / "unrelated-cwd"
        unrelated.mkdir()

        consumer = self.work / "external-consumer.wl"
        consumer.write_text(
            f"Get[{json.dumps(str(source / 'src/SSHFling.wl'))}]\n"
            "status = SSHFling`RunSSHFling[Rest[$ScriptCommandLine]];\n"
            "Exit[If[IntegerQ[status], status, 1]];\n",
            encoding="utf-8",
        )

        fake_runtime = self.work / "fake runtime.py"
        fake_runtime.write_text(
            "import sys\n"
            "expected = ['argument with spaces', 'literal;$()&', 'quote\\'and\"double']\n"
            "if sys.argv[1:] != expected:\n"
            "    print(repr(sys.argv[1:]), file=sys.stderr)\n"
            "    raise SystemExit(41)\n"
            "print('argv ok')\n"
            "raise SystemExit(23)\n",
            encoding="utf-8",
        )
        boundary = self.command(
            "argument-boundaries",
            [
                *mathics,
                consumer,
                "--",
                "argument with spaces",
                "literal;$()&",
                "quote'and\"double",
            ],
            cwd=unrelated,
            env={**env, "SSHFLING_RUNTIME": str(fake_runtime)},
            expected={23},
        )
        self.check(
            "argument-boundary-output",
            boundary.stdout == "argv ok\n",
            f"stdout={boundary.stdout!r}",
        )

        zero_runtime = self.work / "fake zero runtime.py"
        zero_runtime.write_text(
            "import sys\n"
            "if sys.argv[1:]:\n"
            "    print(repr(sys.argv[1:]), file=sys.stderr)\n"
            "    raise SystemExit(42)\n"
            "print('zero argv ok')\n"
            "raise SystemExit(24)\n",
            encoding="utf-8",
        )
        zero = self.command(
            "zero-argument-boundary",
            [*mathics, consumer, "--"],
            cwd=unrelated,
            env={**env, "SSHFLING_RUNTIME": str(zero_runtime)},
            expected={24},
        )
        self.check(
            "zero-argument-output",
            zero.stdout == "zero argv ok\n",
            f"stdout={zero.stdout!r}",
        )

        command = lambda args: [*mathics, consumer, "--", *args]
        self.run_status_cases(command, cwd=unrelated, env=env)

        packaged_version = self.command(
            "packaged-consumer-version",
            [*mathics, source / "test/consumer.wl", "--", "--version"],
            cwd=unrelated,
            env=env,
        )
        self.assert_version_output(packaged_version)

        shutil.rmtree(source)
        self.check("package-removed", not source.exists(), f"path={source}")
        self.command(
            "import-absence",
            [*mathics, consumer, "--", "--version"],
            cwd=unrelated,
            env=env,
            expected=lambda status: status != 0,
        )

    def validate_janet(self) -> None:
        self.probe("janet-version", [self.tools["janet"], "--version"])
        self.probe("jpm-paths", [self.tools["jpm"], "show-paths"])
        archive = self.source_archive()
        source = extract_single_root(archive, self.work / "installed-source")
        local_tree = source / "jpm_tree"
        modpath = local_tree / "lib"
        binpath = local_tree / "bin"
        env = {
            "JANET_PATH": str(modpath),
            "JANET_LIBPATH": str(modpath),
        }
        self.command(
            "jpm-package-install",
            [self.tools["jpm"], "--local", "--offline", "install"],
            cwd=source,
            env=env,
        )
        installed_runtime = modpath / "sshfling/runtime"
        self.verify_runtime(installed_runtime)
        consumer = self.work / "external-consumer.janet"
        consumer.write_text(
            "(import sshfling)\n"
            "(os/exit (sshfling/run (slice (dyn :args) 1)))\n",
            encoding="utf-8",
        )
        unrelated = self.work / "unrelated-cwd"
        unrelated.mkdir()
        command = lambda args: [self.tools["janet"], consumer, *args]
        self.run_status_cases(command, cwd=unrelated, env=env)
        cli = binpath / "sshfling"
        cli_result = self.command("installed-cli-version", [cli, "--version"], cwd=unrelated, env=env)
        self.assert_version_output(cli_result)
        self.command(
            "jpm-package-remove",
            [self.tools["jpm"], "--local", "uninstall"],
            cwd=source,
            env=env,
        )
        self.check("cli-removed", not cli.exists(), f"path={cli}")
        self.command(
            "import-absence",
            [self.tools["janet"], consumer, "--version"],
            cwd=unrelated,
            env=env,
            expected=lambda status: status != 0,
        )
        self.check("package-removed", not installed_runtime.exists(), f"path={installed_runtime}")

    def write_ring_status_wrapper(self, path: Path, script: Path, package_root: Path) -> None:
        ring = shlex.quote(self.tools["ring"])
        script_arg = shlex.quote(str(script))
        package_arg = shlex.quote(str(package_root))
        path.write_text(
            "#!/usr/bin/env sh\n"
            "set -u\n"
            'status_file="${TMPDIR:-/tmp}/sshfling-ring-status.$$"\n'
            "cleanup() {\n"
            '    rm -f -- "$status_file"\n'
            "}\n"
            "trap cleanup EXIT HUP INT TERM\n"
            "SSHFLING_RING_STATUS_FILE=\"$status_file\" \\\n"
            f"SSHFLING_PACKAGE_ROOT=\"${{SSHFLING_PACKAGE_ROOT:-{package_arg}}}\" \\\n"
            f"{ring} {script_arg} \"$@\"\n"
            "ring_status=$?\n"
            'if [ "$ring_status" -ne 0 ]; then\n'
            '    exit "$ring_status"\n'
            "fi\n"
            'if [ ! -s "$status_file" ]; then\n'
            "    exit 1\n"
            "fi\n"
            "status=$(sed -n '1p' \"$status_file\")\n"
            'case "$status" in\n'
            "    ''|*[!0-9]*)\n"
            "        exit 1\n"
            "        ;;\n"
            "esac\n"
            'exit "$status"\n',
            encoding="utf-8",
        )
        path.chmod(0o755)

    def validate_ring(self) -> None:
        self.probe("ring-version", [self.tools["ring"], "-version"])
        archive = self.source_archive()
        source = extract_single_root(archive, self.work / "installed-source")
        self.command("ring-package-metadata", [self.tools["ring"], source / "package.ring"], cwd=source)
        self.verify_runtime(source / "runtime")

        ring_path = Path(self.tools["ring"]).resolve()
        path_env = {"PATH": f"{ring_path.parent}:{self.base_env.get('PATH', '')}"}
        unrelated = self.work / "unrelated-cwd"
        unrelated.mkdir()

        cli = source / "bin/sshfling-ring"
        cli_version = self.command("installed-cli-version", [cli, "--version"], cwd=unrelated, env=path_env)
        self.assert_version_output(cli_version)
        self.command(
            "installed-cli-invalid-option",
            [cli, "--definitely-invalid"],
            cwd=unrelated,
            env=path_env,
            expected={2},
        )

        consumer = self.work / "external-ring-consumer.ring"
        consumer.write_text(
            f"load {json.dumps(str(source / 'lib.ring'))}\n"
            "func commandarguments\n"
            "    aArgs = []\n"
            "    if len(sysargv) >= 3\n"
            "        for nIndex = 3 to len(sysargv) add(aArgs, sysargv[nIndex]) next\n"
            "    ok\n"
            "    return aArgs\n"
            "\n"
            "func main\n"
            "    nStatus = run(commandarguments())\n"
            "    cStatusFile = sysget(\"SSHFLING_RING_STATUS_FILE\")\n"
            "    if cStatusFile != \"\" write(cStatusFile, \"\" + nStatus) ok\n",
            encoding="utf-8",
        )
        wrapper = self.work / "external-ring-consumer"
        self.write_ring_status_wrapper(wrapper, consumer, source)
        self.run_status_cases(lambda args: [wrapper, *args], cwd=unrelated)

        shutil.rmtree(source)
        self.check("cli-removed", not cli.exists(), f"path={cli}")
        self.command(
            "import-absence",
            [wrapper, "--version"],
            cwd=unrelated,
            expected=lambda status: status != 0,
        )
        self.check("package-removed", not source.exists(), f"path={source}")

    def validate_raku(self) -> None:
        self.probe("raku-version", [self.tools["raku"], "--version"])
        archive = self.source_archive()
        source = extract_single_root(archive, self.work / "source with spaces")
        self.verify_runtime(source / "runtime")

        unrelated = self.work / "unrelated-cwd"
        unrelated.mkdir()
        consumer = self.work / "external-consumer.raku"
        consumer.write_text(
            f"use lib {json.dumps(str(source / 'lib'))};\n"
            "use SSHFling;\n"
            "exit run(@*ARGS);\n",
            encoding="utf-8",
        )
        command = lambda args: [self.tools["raku"], consumer, *args]
        self.run_status_cases(command, cwd=unrelated)
        self.command(
            "consumer-argument-boundaries",
            command(["--version", "space value", "semi;colon", "quote'\"value"]),
            cwd=unrelated,
        )
        zero = self.command("consumer-zero-arguments", command([]), cwd=unrelated, expected={0, 2})
        self.check(
            "zero-argument-status",
            zero.returncode in {0, 2},
            f"status={zero.returncode};stdout_bytes={len(zero.stdout)};stderr_bytes={len(zero.stderr)}",
        )
        cli = source / "bin/sshfling-raku"
        cli_result = self.command("installed-cli-version", [cli, "--version"], cwd=unrelated)
        self.assert_version_output(cli_result)
        packaged = self.command(
            "packaged-consumer-version",
            [self.tools["raku"], "-I", source / "lib", source / "test/consumer.raku", "--version"],
            cwd=unrelated,
        )
        self.assert_version_output(packaged)

        shutil.rmtree(source)
        self.check("package-removed", not source.exists(), f"path={source}")
        self.command(
            "import-absence",
            [self.tools["raku"], consumer, "--version"],
            cwd=unrelated,
            expected=lambda status: status != 0,
        )

    def validate_haxe(self) -> None:
        self.probe("haxe-version", [self.tools["haxe"], "--version"])
        self.probe("neko-version", [self.tools["neko"], "-version"])
        self.probe("haxelib-version", [self.tools["haxelib"], "version"])
        archive = self.source_archive()
        source = extract_single_root(archive, self.work / "source with spaces")
        self.verify_runtime(source / "runtime")

        haxelib_repo = self.work / "haxelib-repo"
        self.command("haxelib-setup", [self.tools["haxelib"], "setup", haxelib_repo], cwd=self.work)
        self.command("haxelib-dev-package", [self.tools["haxelib"], "dev", "sshfling", source], cwd=self.work)
        self.command("haxelib-path", [self.tools["haxelib"], "path", "sshfling"], cwd=self.work)

        source_bin = source / "bin"
        source_bin.mkdir(exist_ok=True)
        self.command("haxe-build-cli", [self.tools["haxe"], "build.hxml"], cwd=source)
        cli = source_bin / "sshfling-haxe.n"
        cli_result = self.command("installed-cli-version", [self.tools["neko"], cli, "--version"], cwd=self.work)
        self.assert_version_output(cli_result)

        unrelated = self.work / "unrelated-cwd"
        unrelated.mkdir()
        consumer_dir = self.work / "external-consumer"
        consumer_dir.mkdir()
        consumer = consumer_dir / "Consumer.hx"
        consumer.write_text(
            "import sshfling.SSHFling;\n"
            "\n"
            "class Consumer {\n"
            "  static function main():Void {\n"
            "    Sys.exit(SSHFling.run(Sys.args()));\n"
            "  }\n"
            "}\n",
            encoding="utf-8",
        )
        consumer_neko = self.work / "consumer.n"
        compile_consumer = [
            self.tools["haxe"],
            "-lib",
            "sshfling",
            "-cp",
            consumer_dir,
            "-main",
            "Consumer",
            "-neko",
            consumer_neko,
        ]
        self.command("external-consumer-build", compile_consumer, cwd=unrelated)
        command = lambda args: [self.tools["neko"], consumer_neko, *args]
        self.run_status_cases(command, cwd=unrelated)
        self.command(
            "consumer-argument-boundaries",
            command(["--version", "space value", "semi;colon", "quote'\"value"]),
            cwd=unrelated,
        )
        zero = self.command("consumer-zero-arguments", command([]), cwd=unrelated, expected={0, 2})
        self.check(
            "zero-argument-status",
            zero.returncode in {0, 2},
            f"status={zero.returncode};stdout_bytes={len(zero.stdout)};stderr_bytes={len(zero.stderr)}",
        )

        packaged_consumer = self.work / "packaged-consumer.n"
        self.command(
            "packaged-consumer-build",
            [
                self.tools["haxe"],
                "-lib",
                "sshfling",
                "-cp",
                source / "test",
                "-main",
                "Consumer",
                "-neko",
                packaged_consumer,
            ],
            cwd=unrelated,
        )
        packaged = self.command(
            "packaged-consumer-version",
            [self.tools["neko"], packaged_consumer, "--version"],
            cwd=unrelated,
        )
        self.assert_version_output(packaged)

        shutil.rmtree(source)
        self.check("package-removed", not source.exists(), f"path={source}")
        self.command(
            "import-absence",
            compile_consumer,
            cwd=unrelated,
            expected=lambda status: status != 0,
        )

    def write_apl_status_wrapper(self, path: Path, source: Path, consumer: Path, package_root: Path) -> None:
        apl = shlex.quote(self.tools["apl"])
        source_arg = shlex.quote(str(source))
        consumer_arg = shlex.quote(str(consumer))
        package_arg = shlex.quote(str(package_root))
        path.write_text(
            "#!/usr/bin/env sh\n"
            "set -u\n"
            'status_file="${TMPDIR:-/tmp}/sshfling-apl-status.$$"\n'
            'stdout_file="${TMPDIR:-/tmp}/sshfling-apl-stdout.$$"\n'
            "cleanup() {\n"
            '    rm -f -- "$status_file" "$stdout_file"\n'
            "}\n"
            "emit_stdout() {\n"
            '    if [ -f "$stdout_file" ]; then\n'
            '        sed \'${/^$/d;}\' "$stdout_file"\n'
            "    fi\n"
            "}\n"
            "trap cleanup EXIT HUP INT TERM\n"
            "SSHFLING_APL_STATUS_FILE=\"$status_file\" \\\n"
            f"SSHFLING_PACKAGE_ROOT=\"${{SSHFLING_PACKAGE_ROOT:-{package_arg}}}\" \\\n"
            f"{apl} -s --OFF -f {source_arg} -f {consumer_arg} -- \"$@\" >\"$stdout_file\"\n"
            "apl_status=$?\n"
            'if [ "$apl_status" -ne 0 ]; then\n'
            "    emit_stdout\n"
            '    exit "$apl_status"\n'
            "fi\n"
            'if [ ! -s "$status_file" ]; then\n'
            "    emit_stdout\n"
            "    exit 1\n"
            "fi\n"
            "status=$(sed -n '1p' \"$status_file\")\n"
            'case "$status" in\n'
            "    ''|*[!0-9]*)\n"
            "        emit_stdout\n"
            "        exit 1\n"
            "        ;;\n"
            "esac\n"
            "emit_stdout\n"
            'exit "$status"\n',
            encoding="utf-8",
        )
        path.chmod(0o755)

    def validate_apl(self) -> None:
        self.probe("apl-version", [self.tools["apl"], "--version"])
        archive = self.source_archive()
        source = extract_single_root(archive, self.work / "source")
        self.verify_runtime(source / "runtime")

        env = {"SSHFLING_PACKAGE_ROOT": str(source)}
        unrelated = self.work / "unrelated-cwd"
        unrelated.mkdir()
        consumer = self.work / "external-consumer.apl"
        consumer.write_text(
            "Status←SSHFling∆Run SSHFling∆ApplicationArgs ⎕ARG\n"
            "SSHFling∆WriteStatus Status\n",
            encoding="utf-8",
        )
        wrapper = self.work / "external-apl-consumer"
        self.write_apl_status_wrapper(wrapper, source / "src/sshfling.apl", consumer, source)
        self.run_status_cases(lambda args: [wrapper, *args], cwd=unrelated, env=env)

        packaged = self.work / "packaged-apl-consumer"
        self.write_apl_status_wrapper(packaged, source / "src/sshfling.apl", source / "test/consumer.apl", source)
        packaged_version = self.command("packaged-consumer-version", [packaged, "--version"], cwd=unrelated, env=env)
        self.assert_version_output(packaged_version)

        shutil.rmtree(source)
        self.check("package-removed", not source.exists(), f"path={source}")
        self.command(
            "import-absence",
            [wrapper, "--version"],
            cwd=unrelated,
            env=env,
            expected=lambda status: status != 0,
        )

    def validate_j(self) -> None:
        self.probe(
            "j-version",
            [self.tools["jconsole"], "-js", "echo 9!:14''", "exit 0"],
        )
        archive = self.source_archive()
        source = extract_single_root(archive, self.work / "source")
        package = self.work / "j-addons/sshfling"
        package.parent.mkdir(parents=True)
        shutil.copytree(source, package, copy_function=shutil.copy2)
        self.check("j-addon-install", package.is_dir(), f"path={package};manifest=manifest.ijs")
        self.verify_runtime(package / "runtime")
        consumer = self.work / "external-consumer.ijs"
        package_literal = "'" + str(package / "src/sshfling.ijs").replace("'", "''") + "'"
        consumer.write_text(
            f"load {package_literal}\n"
            "exit run_sshfling_ 2}.ARGV\n",
            encoding="utf-8",
        )
        env = {"SSHFLING_PACKAGE_ROOT": str(package)}
        unrelated = self.work / "unrelated-cwd"
        unrelated.mkdir()
        command = lambda args: [self.tools["jconsole"], consumer, *args]
        smoke = self.work / "smoke project's\nnewline"
        self.run_status_cases(command, cwd=unrelated, env=env, smoke=smoke)
        self.check(
            "consumer-init-cwd-isolation",
            not (unrelated / ".env").exists(),
            f"cwd={unrelated};unexpected_deployment={unrelated / '.env'}",
        )
        cli_result = self.command(
            "installed-cli-version",
            [self.tools["jconsole"], package / "bin/sshfling.ijs", "--version"],
            cwd=unrelated,
            env=env,
        )
        self.assert_version_output(cli_result)
        shutil.rmtree(package)
        self.check("package-removed", not package.exists(), f"path={package}")
        self.command(
            "import-absence",
            [self.tools["jconsole"], "-js", f"exit fexist {package_literal}"],
            cwd=unrelated,
            env=env,
        )

    def validate_ballerina(self) -> None:
        self.probe("bal-version", [self.tools["bal"], "version"])
        java = os.environ.get("SSHFLING_JAVA", "java")
        self.probe("java-version", [java, "-version"])
        archive = self.source_archive()
        source = extract_single_root(archive, self.work / "source")
        env = {
            "SSHFLING_PACKAGE_ROOT": str(source),
            "JAVA_OPTS": f"-Duser.home={self.base_env['HOME']}",
            "_JAVA_OPTIONS": f"-Duser.home={self.base_env['HOME']}",
        }
        self.command(
            "ballerina-package-test",
            [self.tools["bal"], "test", "--offline", "--sticky", source],
            cwd=self.work,
            env=env,
        )
        self.command(
            "ballerina-pack",
            [self.tools["bal"], "pack", "--offline", "--sticky", source],
            cwd=self.work,
            env=env,
        )
        bala_archives = sorted((source / "target/bala").glob("*.bala"))
        self.check(
            "bala-archive-count",
            len(bala_archives) == 1,
            f"archives={[path.name for path in bala_archives]}",
        )
        self.record_archive("bala-archive", bala_archives[0])
        self.command(
            "local-repository-push",
            [self.tools["bal"], "push", "--repository=local", bala_archives[0]],
            cwd=self.work,
            env=env,
        )
        local_package = (
            Path(self.base_env["HOME"])
            / ".ballerina/repositories/local/bala/grwlx/sshfling"
            / self.version
            / "any"
        )
        self.check(
            "local-repository-install",
            local_package.is_dir(),
            f"path={local_package};version={self.version}",
        )
        installed_runtime = local_package / "resources/runtime"
        expected_runtime = file_inventory(self.canonical)
        actual_runtime = file_inventory(installed_runtime) if installed_runtime.is_dir() else {}
        missing_runtime = sorted(set(expected_runtime) - set(actual_runtime))
        digest_mismatches = sorted(
            name
            for name in set(expected_runtime) & set(actual_runtime)
            if expected_runtime[name][0] != actual_runtime[name][0]
        )
        extra_runtime = sorted(set(actual_runtime) - set(expected_runtime))
        self.check(
            "installed-resources",
            not missing_runtime and not digest_mismatches,
            f"root={installed_runtime};files={len(actual_runtime)};"
            f"canonical_files={len(expected_runtime)};"
            f"missing={','.join(missing_runtime) or 'none'};"
            f"digest_mismatches={','.join(digest_mismatches) or 'none'};"
            f"extra={','.join(extra_runtime) or 'none'};mode_normalized_by_bala=yes",
        )

        consumer = self.work / "external-ballerina-consumer"
        tests = consumer / "tests"
        tests.mkdir(parents=True)
        (consumer / "Ballerina.toml").write_text(
            "[package]\n"
            "org = \"external\"\n"
            "name = \"consumer\"\n"
            "version = \"0.1.0\"\n"
            "distribution = \"2201.12.0\"\n\n"
            "[[dependency]]\n"
            "org = \"grwlx\"\n"
            "name = \"sshfling\"\n"
            f"version = \"{self.version}\"\n"
            "repository = \"local\"\n",
            encoding="utf-8",
        )
        (consumer / "main.bal").write_text(
            "import ballerina/io;\n"
            "import grwlx/sshfling;\n\n"
            "public function main() {\n"
            "    sshfling:RunResult result = sshfling:runAndCapture([\"--version\"]);\n"
            "    io:print(result.stdout);\n"
            "}\n",
            encoding="utf-8",
        )
        smoke = self.work / "smoke"
        tests.joinpath("consumer_test.bal").write_text(
            "import ballerina/test;\n"
            "import grwlx/sshfling;\n\n"
            "@test:Config {}\n"
            "function versionStatus() {\n"
            "    test:assertEquals(sshfling:run([\"--version\"]), 0);\n"
            "}\n\n"
            "@test:Config {}\n"
            "function invalidStatus() {\n"
            "    test:assertEquals(sshfling:run([\"--definitely-invalid\"]), 2);\n"
            "}\n\n"
            "@test:Config {}\n"
            "function initStatus() {\n"
            f"    test:assertEquals(sshfling:run([\"init\", {json.dumps(str(smoke))}, \"--force\", \"--session-seconds\", \"60\"]), 0);\n"
            "}\n\n"
            "@test:Config {}\n"
            "function missingRuntimeStatus() {\n"
            "    test:assertEquals(sshfling:run([]), 127);\n"
            "}\n",
            encoding="utf-8",
        )
        self.command(
            "external-consumer-test",
            [
                self.tools["bal"],
                "test",
                "--offline",
                "--sticky",
                "--tests",
                "versionStatus,invalidStatus,initStatus",
                consumer,
            ],
            cwd=self.work,
            env=env,
        )
        self.verify_init(smoke)
        missing_env = {**env, "SSHFLING_RUNTIME": str(self.work / "missing-runtime.py")}
        self.command(
            "consumer-missing-runtime",
            [
                self.tools["bal"],
                "test",
                "--offline",
                "--sticky",
                "--tests",
                "missingRuntimeStatus",
                consumer,
            ],
            cwd=self.work,
            env=missing_env,
        )
        self.command(
            "external-consumer-build",
            [self.tools["bal"], "build", "--offline", "--sticky", consumer],
            cwd=self.work,
            env=env,
        )
        executables = sorted((consumer / "target/bin").glob("*.jar"))
        self.check(
            "external-consumer-executable",
            len(executables) == 1,
            f"executables={[path.name for path in executables]}",
        )
        version_output = self.command(
            "consumer-version-output",
            [java, "-jar", executables[0]],
            cwd=self.work,
            env=env,
        )
        self.assert_version_output(version_output)

        shutil.rmtree(local_package)
        shutil.rmtree(consumer / "target", ignore_errors=True)
        self.command(
            "import-absence",
            [self.tools["bal"], "build", "--offline", "--sticky", consumer],
            cwd=self.work,
            env=env,
            expected=lambda status: status != 0,
        )
        self.check("package-removed", not local_package.exists(), f"path={local_package}")

    def validate_roc(self) -> None:
        self.probe("roc-version", [self.tools["roc"], "version"])
        self.command("roc-package-check", [self.tools["roc"], "check", self.stage / "main.roc"], cwd=self.stage)
        archive = self.source_archive()
        source = extract_single_root(archive, self.work / "installed-source")
        self.command("roc-package-build", [self.tools["roc"], "build", source / "main.roc"], cwd=source)
        cli = source / "main"
        self.check("roc-cli-built", cli.is_file() and os.access(cli, os.X_OK), f"path={cli}")
        self.verify_runtime(source / "runtime")

        package_literal = json.dumps(str(source / "package.roc"))
        consumer_dir = self.work / "external-roc-consumer"
        consumer_dir.mkdir()
        consumer = consumer_dir / "consumer.roc"
        consumer.write_text(
            "app [main!] {\n"
            "    cli: platform \"https://github.com/roc-lang/basic-cli/releases/download/0.20.0/X73hGh05nNTkDHU06FHC0YfFaQB1pimX7gncRcao5mU.tar.br\",\n"
            f"    sshfling: {package_literal},\n"
            "}\n\n"
            "import cli.Arg exposing [Arg]\n"
            "import sshfling.SSHFling\n\n"
            "main! : List Arg => Result {} _\n"
            "main! = |raw_args|\n"
            "    status = SSHFling.run!(List.map(List.drop_first(raw_args, 1), Arg.display))?\n"
            "    if status == 0 then\n"
            "        Ok({})\n"
            "    else\n"
            "        Err(Exit(status, \"\"))\n",
            encoding="utf-8",
        )
        env = {
            "SSHFLING_RUNTIME": str(source / "runtime/sshfling.py"),
            "SSHFLING_TEMPLATE_DIR": str(source / "runtime/templates"),
        }
        self.command("external-consumer-check", [self.tools["roc"], "check", consumer], cwd=consumer_dir, env=env)
        self.command("external-consumer-build", [self.tools["roc"], "build", consumer], cwd=consumer_dir, env=env)
        consumer_cli = consumer_dir / "consumer"
        self.check("external-consumer-executable", consumer_cli.is_file(), f"path={consumer_cli}")
        unrelated = self.work / "unrelated-cwd"
        unrelated.mkdir()
        self.run_status_cases(lambda args: [consumer_cli, *args], cwd=unrelated, env=env)
        cli_result = self.command("installed-cli-version", [cli, "--version"], cwd=unrelated, env=env)
        self.assert_version_output(cli_result)

        shutil.rmtree(source)
        self.check("package-removed", not source.exists(), f"path={source}")
        self.command(
            "import-absence",
            [self.tools["roc"], "check", consumer],
            cwd=consumer_dir,
            env=env,
            expected=lambda status: status != 0,
        )

    def validate_common_lisp(self) -> None:
        self.probe("sbcl-version", [self.tools["sbcl"], "--version"])
        archive = self.source_archive()
        install_root = self.work / "installed-systems"
        source = extract_single_root(archive, install_root)
        registry = f'(:source-registry (:tree "{install_root}") :ignore-inherited-configuration)'
        env = {"CL_SOURCE_REGISTRY": registry}
        self.command(
            "asdf-compile-install",
            [
                self.tools["sbcl"],
                "--noinform",
                "--non-interactive",
                "--eval",
                "(require :asdf)",
                "--eval",
                '(asdf:compile-system "sshfling" :force t)',
            ],
            cwd=self.work,
            env=env,
        )
        self.verify_runtime(source / "runtime")
        consumer = self.work / "external-consumer.lisp"
        consumer.write_text(
            "(require :asdf)\n"
            '(asdf:load-system "sshfling")\n'
            "(uiop:quit (sshfling:run (uiop:command-line-arguments)))\n",
            encoding="utf-8",
        )
        unrelated = self.work / "unrelated-cwd"
        unrelated.mkdir()
        self.run_status_cases(
            lambda args: [self.tools["sbcl"], "--noinform", "--disable-debugger", "--script", consumer, *args],
            cwd=unrelated,
            env=env,
        )
        shutil.rmtree(source)
        shutil.rmtree(self.work / "cache", ignore_errors=True)
        self.command(
            "import-absence",
            [
                self.tools["sbcl"],
                "--noinform",
                "--non-interactive",
                "--eval",
                "(require :asdf)",
                "--eval",
                '(uiop:quit (if (asdf:find-system "sshfling" nil) 1 0))',
            ],
            cwd=unrelated,
            env=env,
        )

    def validate_scheme(self) -> None:
        self.probe("guile-version", [self.tools["guile"], "--version"])
        self.probe("make-version", [self.tools["make"], "--version"])
        dist_prefix = self.work / "dist-prefix"
        env = {"GUILE_AUTO_COMPILE": "0"}
        self.command("configure-dist", [self.stage / "configure", f"--prefix={dist_prefix}"], cwd=self.stage, env=env)
        self.command("guile-native-dist", [self.tools["make"], "dist"], cwd=self.stage, env=env)
        archive = self.stage / f"sshfling-guile-{self.version}.tar.gz"
        self.record_archive("source-archive", archive)
        source = extract_single_root(archive, self.work / "source")
        prefix = self.work / "prefix"
        self.command("configure-install", [source / "configure", f"--prefix={prefix}"], cwd=source, env=env)
        self.command("guile-compile-check", [self.tools["make"], "check"], cwd=source, env=env)
        self.command("guile-install", [self.tools["make"], "install"], cwd=source, env=env)
        runtime = prefix / "share/sshfling-guile/runtime"
        self.verify_runtime(runtime)
        module_dir = prefix / "share/guile/site/3.0"
        object_dir = prefix / "lib/guile/3.0/site-ccache"
        consumer = self.work / "external-consumer.scm"
        consumer.write_text(
            "(use-modules (sshfling))\n(exit (run (cdr (command-line))))\n",
            encoding="utf-8",
        )
        unrelated = self.work / "unrelated-cwd"
        unrelated.mkdir()
        command = lambda args: [
            self.tools["guile"],
            "--no-auto-compile",
            "-L",
            module_dir,
            "-C",
            object_dir,
            consumer,
            *args,
        ]
        self.run_status_cases(command, cwd=unrelated, env=env)
        cli = prefix / "bin/sshfling-guile"
        cli_result = self.command("installed-cli-version", [cli, "--version"], cwd=unrelated, env=env)
        self.assert_version_output(cli_result)
        self.command("guile-uninstall", [self.tools["make"], "uninstall"], cwd=source, env=env)
        self.check("cli-removed", not cli.exists(), f"path={cli}")
        self.command(
            "import-absence",
            command(["--version"]),
            cwd=unrelated,
            env=env,
            expected=lambda status: status != 0,
        )

    def validate_prolog(self) -> None:
        self.probe("swipl-version", [self.tools["swipl"], "--version"])
        archive = self.work / f"sshfling-{self.version}.tgz"
        archive_tree(self.stage, archive, f"sshfling-{self.version}")
        self.record_archive("source-archive", archive)
        pack_root = self.work / "packs"
        pack_root.mkdir()
        install_goal = (
            "use_module(library(prolog_pack)),"
            f"pack_install({prolog_atom(str(archive.resolve()))},["
            f"package_directory({prolog_atom(str(pack_root))}),name(sshfling),version({prolog_atom(self.version)}),"
            "interactive(false),"
            "silent(true),test(false),git(false)]),halt"
        )
        self.command("pack-install", [self.tools["swipl"], "-q", "-g", install_goal], cwd=self.work)
        candidates = [path for path in pack_root.iterdir() if path.is_dir() and (path / "pack.pl").is_file()]
        self.check("pack-layout", len(candidates) == 1, f"candidates={[str(path) for path in candidates]}")
        installed = candidates[0]
        self.verify_runtime(installed / "runtime")
        consumer = self.work / "external-consumer.pl"
        consumer.write_text(
            ":- use_module(library(prolog_pack)).\n"
            ":- initialization(main, main).\n"
            "main(Arguments) :-\n"
            "    getenv('SSHFLING_PROLOG_PACK_DIR', Directory),\n"
            "    pack_attach(Directory, [duplicate(replace)]),\n"
            "    use_module(library(sshfling)),\n"
            "    sshfling:run(Arguments, Status),\n"
            "    halt(Status).\n",
            encoding="utf-8",
        )
        unrelated = self.work / "unrelated-cwd"
        unrelated.mkdir()
        env = {"SSHFLING_PROLOG_PACK_DIR": str(installed)}
        command = lambda args: [self.tools["swipl"], "-q", "-s", consumer, "--", *args]
        self.run_status_cases(command, cwd=unrelated, env=env)
        remove_goal = (
            "use_module(library(prolog_pack)),"
            f"pack_attach({prolog_atom(str(installed))},[duplicate(replace)]),"
            "pack_remove(sshfling),halt"
        )
        self.command("pack-remove", [self.tools["swipl"], "-q", "-g", remove_goal], cwd=self.work)
        self.check("package-removed", not installed.exists(), f"path={installed}")
        self.command(
            "import-absence",
            command(["--version"]),
            cwd=unrelated,
            env=env,
            expected=lambda status: status != 0,
        )

    def validate_smalltalk(self) -> None:
        self.probe("gst-version", [self.tools["gst"], "--version"])
        self.probe("gst-package-version", [self.tools["gst-package"], "--version"])
        archive = self.source_archive()
        source = extract_single_root(archive, self.work / "source")
        dist = self.work / "dist"
        self.command(
            "gst-package-dist",
            [
                self.tools["gst-package"],
                f"--srcdir={source}",
                "--dist",
                "--copy",
                "--all-files",
                f"--distdir={dist}",
                source / "package.xml",
            ],
            cwd=source,
        )
        package_root = dist / "SSHFling"
        if not package_root.exists():
            package_root = dist
        self.check("gst-package-layout", (package_root / "src/SSHFling.st").is_file(), f"path={package_root}")
        self.verify_runtime(package_root / "runtime")
        consumer = self.work / "external-smalltalk-consumer.st"
        consumer.write_text(
            "ObjectMemory quit: (SSHFling run: Smalltalk arguments).\n",
            encoding="utf-8",
        )
        unrelated = self.work / "unrelated-cwd"
        unrelated.mkdir()
        env = {"SSHFLING_PACKAGE_ROOT": str(package_root)}
        command = lambda args: [
            self.tools["gst"],
            package_root / "src/SSHFling.st",
            "-f",
            consumer,
            *args,
        ]
        self.run_status_cases(command, cwd=unrelated, env=env)
        package_smoke = self.work / "package-consumer-smoke"
        self.command(
            "package-test-consumer",
            [
                self.tools["gst"],
                package_root / "src/SSHFling.st",
                "-f",
                package_root / "test/consumer.st",
                package_smoke,
            ],
            cwd=unrelated,
            env=env,
        )
        self.verify_init(package_smoke)
        shutil.rmtree(package_root)
        self.check("package-removed", not package_root.exists(), f"path={package_root}")
        self.check("import-absence", not (package_root / "src/SSHFling.st").exists(), f"path={package_root / 'src/SSHFling.st'}")

    def validate_r(self) -> None:
        self.probe("R-version", [self.tools["R"], "--version"])
        self.probe("Rscript-version", [self.tools["Rscript"], "--version"])
        env = {
            "R_ENVIRON_USER": "/dev/null",
            "R_PROFILE_USER": "/dev/null",
            "_R_CHECK_FORCE_SUGGESTS_": "false",
            "_R_CHECK_CRAN_INCOMING_REMOTE_": "false",
        }
        self.command(
            "R-CMD-build",
            [self.tools["R"], "CMD", "build", "--no-build-vignettes", "--no-manual", self.stage],
            cwd=self.work,
            env=env,
        )
        archive = self.work / f"sshfling_{self.version}.tar.gz"
        self.record_archive("source-archive", archive)
        check_dir = self.work / "check"
        check_dir.mkdir()
        self.command(
            "R-CMD-check",
            [self.tools["R"], "CMD", "check", "--no-manual", "--no-build-vignettes", archive],
            cwd=check_dir,
            env=env,
        )
        library = self.work / "R-library"
        library.mkdir()
        self.command(
            "R-CMD-install",
            [self.tools["R"], "CMD", "INSTALL", f"--library={library}", archive],
            cwd=self.work,
            env=env,
        )
        self.verify_runtime(library / "sshfling/runtime")
        consumer = self.work / "external-consumer.R"
        consumer.write_text(
            "suppressPackageStartupMessages(library(sshfling))\n"
            "quit(save = \"no\", status = run(commandArgs(trailingOnly = TRUE)))\n",
            encoding="utf-8",
        )
        unrelated = self.work / "unrelated-cwd"
        unrelated.mkdir()
        consumer_env = {**env, "R_LIBS_USER": str(library)}
        command = lambda args: [self.tools["Rscript"], "--vanilla", consumer, *args]
        self.run_status_cases(command, cwd=unrelated, env=consumer_env)
        self.command(
            "R-CMD-remove",
            [self.tools["R"], "CMD", "REMOVE", f"--library={library}", "sshfling"],
            cwd=self.work,
            env=env,
        )
        self.check("package-removed", not (library / "sshfling").exists(), f"library={library}")
        self.command(
            "import-absence",
            [
                self.tools["Rscript"],
                "--vanilla",
                "-e",
                'quit(status=if (requireNamespace("sshfling", quietly=TRUE)) 1L else 0L)',
            ],
            cwd=unrelated,
            env=consumer_env,
        )

    def validate_erlang(self) -> None:
        self.probe(
            "erl-version",
            [self.tools["erl"], "-noshell", "-eval", 'io:format("OTP ~s~n", [erlang:system_info(otp_release)]), halt().'],
        )
        self.probe("erlc-available", [self.tools["erlc"], "-v"])
        self.source_archive()
        library_root = self.work / "otp-lib"
        package = library_root / f"sshfling-{self.version}"
        ebin = package / "ebin"
        ebin.mkdir(parents=True)
        shutil.copytree(self.stage / "priv", package / "priv", copy_function=shutil.copy2)
        self.command(
            "erlc-package-build",
            [self.tools["erlc"], "-Werror", "-o", ebin, self.stage / "src/sshfling.erl"],
            cwd=self.work,
        )
        shutil.copy2(self.stage / "src/sshfling.app.src", ebin / "sshfling.app")
        binary_archive = self.work / f"sshfling-{self.version}-otp.tar.gz"
        archive_tree(package, binary_archive, package.name)
        self.record_archive("otp-archive", binary_archive)
        self.verify_runtime(package / "priv/runtime")
        consumer_dir = self.work / "external-erlang-consumer"
        consumer_ebin = consumer_dir / "ebin"
        consumer_ebin.mkdir(parents=True)
        consumer_source = consumer_dir / "sshfling_external.erl"
        consumer_source.write_text(
            "-module(sshfling_external).\n"
            "-export([main/0]).\n"
            "main() ->\n"
            "    ok = application:load(sshfling),\n"
            "    halt(sshfling:run(init:get_plain_arguments())).\n",
            encoding="utf-8",
        )
        self.command(
            "external-consumer-build",
            [self.tools["erlc"], "-Werror", "-o", consumer_ebin, consumer_source],
            cwd=consumer_dir,
        )
        unrelated = self.work / "unrelated-cwd"
        unrelated.mkdir()
        env = {"ERL_LIBS": str(library_root)}
        command = lambda args: [
            self.tools["erl"],
            "-noshell",
            "-pa",
            consumer_ebin,
            "-s",
            "sshfling_external",
            "main",
            "-extra",
            *args,
        ]
        self.run_status_cases(command, cwd=unrelated, env=env)
        shutil.rmtree(package)
        self.command(
            "import-absence",
            [
                self.tools["erl"],
                "-noshell",
                "-eval",
                'case code:which(sshfling) of non_existing -> halt(0); _ -> halt(1) end.',
            ],
            cwd=unrelated,
            env=env,
        )
        self.check("package-removed", not package.exists(), f"path={package}")

    def validate_elixir(self) -> None:
        self.probe("elixir-version", [self.tools["elixir"], "--version"])
        self.probe("mix-version", [self.tools["mix"], "--version"])
        archive = self.source_archive()
        mix_env = {
            "MIX_HOME": str(self.work / "mix-home"),
            "HEX_HOME": str(self.work / "hex-home"),
            "MIX_ENV": "dev",
        }
        self.command("mix-package-compile", [self.tools["mix"], "compile", "--warnings-as-errors"], cwd=self.stage, env=mix_env)
        package_source = extract_single_root(archive, self.work / "installed-source")
        consumer = self.work / "external-mix-consumer"
        consumer.mkdir()
        package_literal = json.dumps(str(package_source))
        (consumer / "mix.exs").write_text(
            "defmodule ExternalConsumer.MixProject do\n"
            "  use Mix.Project\n"
            f"  def project, do: [app: :external_consumer, version: \"0.1.0\", elixir: \">= 1.14.0\", deps: [{{:sshfling, path: {package_literal}}}]]\n"
            "  def application, do: []\n"
            "end\n",
            encoding="utf-8",
        )
        script = consumer / "consumer.exs"
        script.write_text("System.halt(SSHFling.run(System.argv()))\n", encoding="utf-8")
        self.command("mix-deps-get", [self.tools["mix"], "deps.get"], cwd=consumer, env=mix_env)
        self.command("mix-deps-compile", [self.tools["mix"], "deps.compile", "--force"], cwd=consumer, env=mix_env)
        self.command("external-consumer-build", [self.tools["mix"], "compile", "--warnings-as-errors"], cwd=consumer, env=mix_env)
        installed_runtime = consumer / "_build/dev/lib/sshfling/priv/runtime"
        self.verify_runtime(installed_runtime)
        unrelated = self.work / "unrelated-cwd"
        unrelated.mkdir()
        command = lambda args: [self.tools["mix"], "run", script, *args]
        self.run_status_cases(command, cwd=consumer, env=mix_env)
        self.command("mix-deps-clean", [self.tools["mix"], "deps.clean", "sshfling", "--unlock"], cwd=consumer, env=mix_env)
        shutil.rmtree(package_source)
        self.check("package-removed", not installed_runtime.exists(), f"path={installed_runtime}")
        self.command(
            "import-absence",
            [self.tools["mix"], "run", script, "--version"],
            cwd=consumer,
            env=mix_env,
            expected=lambda status: status != 0,
        )

    def validate_gleam(self) -> None:
        self.probe("gleam-version", [self.tools["gleam"], "--version"])
        self.probe(
            "erl-version",
            [self.tools["erl"], "-noshell", "-eval", 'io:format("OTP ~s~n", [erlang:system_info(otp_release)]), halt().'],
        )
        self.command("gleam-package-check", [self.tools["gleam"], "check"], cwd=self.stage)
        before = {path.resolve() for path in self.stage.rglob("*.tar*")}
        self.command("gleam-hex-tarball", [self.tools["gleam"], "export", "hex-tarball"], cwd=self.stage)
        after = {path.resolve() for path in self.stage.rglob("*.tar*")}
        archives = sorted(after - before)
        self.check("hex-archive-count", len(archives) == 1, f"archives={[path.name for path in archives]}")
        archive = archives[0]
        self.record_archive("hex-archive", archive)
        self.check("hex-archive-version", self.version in archive.name, f"archive={archive.name}")
        install_source = self.work / f"sshfling-{self.version}"
        with tarfile.open(archive, "r:") as outer:
            member = outer.getmember("contents.tar.gz")
            stream = outer.extractfile(member)
            if stream is None:
                raise ValidationFailure("gleam: Hex archive has no contents stream")
            payload = stream.read()
        with tarfile.open(fileobj=io.BytesIO(payload), mode="r:gz") as contents:
            safe_extract(contents, install_source)
        consumer = self.work / "external-gleam-consumer"
        source_dir = consumer / "src"
        source_dir.mkdir(parents=True)
        (consumer / "gleam.toml").write_text(
            "name = \"external_consumer\"\n"
            "version = \"0.1.0\"\n"
            "target = \"erlang\"\n"
            "[dependencies]\n"
            f"sshfling = {{ path = {json.dumps(str(install_source))} }}\n",
            encoding="utf-8",
        )
        smoke = self.work / "smoke"
        modules = {
            "version": 'let assert 0 = sshfling.run(["--version"])',
            "invalid": 'let assert 2 = sshfling.run(["--definitely-invalid"])',
            "init_case": f'let assert 0 = sshfling.run(["init", {json.dumps(str(smoke))}, "--force", "--session-seconds", "60"])',
            "missing": "let assert 127 = sshfling.run([])",
        }
        for name, body in modules.items():
            (source_dir / f"{name}.gleam").write_text(
                f"import sshfling\n\npub fn main() {{\n  {body}\n  Nil\n}}\n",
                encoding="utf-8",
            )
        self.command("external-consumer-build", [self.tools["gleam"], "build"], cwd=consumer)
        installed_candidates = list((consumer / "build").glob("*/erlang/sshfling/priv/runtime"))
        self.check("gleam-installed-layout", len(installed_candidates) == 1, f"candidates={installed_candidates}")
        self.verify_runtime(installed_candidates[0])
        version = self.command("consumer-version", [self.tools["gleam"], "run", "-m", "version"], cwd=consumer)
        self.assert_version_output(version)
        self.command("consumer-invalid-option", [self.tools["gleam"], "run", "-m", "invalid"], cwd=consumer)
        self.command("consumer-init", [self.tools["gleam"], "run", "-m", "init_case"], cwd=consumer)
        self.verify_init(smoke)
        self.command(
            "consumer-missing-runtime",
            [self.tools["gleam"], "run", "-m", "missing"],
            cwd=consumer,
            env={"SSHFLING_RUNTIME": str(self.work / "missing-runtime.py")},
        )
        shutil.rmtree(install_source)
        shutil.rmtree(consumer / "build", ignore_errors=True)
        self.command(
            "import-absence",
            [self.tools["gleam"], "check"],
            cwd=consumer,
            expected=lambda status: status != 0,
        )


TOOL_REQUIREMENTS: dict[str, tuple[str, ...]] = {
    "haskell": ("ghc", "cabal"),
    "ocaml": ("ocamlc", "dune"),
    "common-lisp": ("sbcl",),
    "scheme": ("guile", "make"),
    "prolog": ("swipl",),
    "smalltalk": ("gst", "gst-package"),
    "ballerina": ("bal",),
    "roc": ("roc",),
    "janet": ("janet", "jpm"),
    "ring": ("ring",),
    "raku": ("raku",),
    "haxe": ("haxe", "neko", "haxelib"),
    "apl": ("apl",),
    "j": ("jconsole",),
    "julia": ("julia",),
    "matlab": ("octave-cli",),
    "wolfram-language": ("mathics",),
    "r": ("R", "Rscript"),
    "q": ("q",),
    "erlang": ("erl", "erlc"),
    "elixir": ("elixir", "mix"),
    "gleam": ("gleam", "erl"),
}


NATIVE_RUNNERS = {
    "haskell",
    "janet",
    "ring",
    "raku",
    "haxe",
    "apl",
    "ballerina",
    "roc",
    "j",
    "julia",
    "matlab",
    "wolfram-language",
    "ocaml",
    "common-lisp",
    "scheme",
    "prolog",
    "smalltalk",
    "r",
    "erlang",
    "elixir",
    "gleam",
}


def resolve_tools(language: Language) -> tuple[dict[str, str], list[str]]:
    requirements = TOOL_REQUIREMENTS.get(language.identifier)
    if requirements is None:
        raise ValidationFailure(f"no explicit tool requirements for {language.identifier}")
    tools: dict[str, str] = {}
    missing: list[str] = []
    for name in requirements:
        path = shutil.which(name)
        if path:
            tools[name] = path
        else:
            missing.append(name)
    return tools, missing


def main() -> int:
    temp_root: Path | None = None
    evidence: Evidence | None = None
    lock_fd: int | None = None
    try:
        languages = load_languages()
        args = parse_arguments(languages)
        selected = [
            language
            for language in languages
            if not args.language or language.identifier in args.language
        ]
        if args.list:
            print("id\tlabel\ttools\tnative_validation")
            for language in selected:
                print(
                    f"{language.identifier}\t{language.label}\t"
                    f"{'+'.join(TOOL_REQUIREMENTS[language.identifier])}\t"
                    f"{'yes' if language.identifier in NATIVE_RUNNERS else 'structural-only'}"
                )
            return 0

        lock_fd = os.open(REPO_ROOT / "packaging", os.O_RDONLY)
        fcntl.flock(lock_fd, fcntl.LOCK_EX)
        evidence = Evidence(args.evidence)
        evidence.record(
            "validator",
            "INFO",
            "start",
            status=0,
            command=shlex.join(sys.argv),
            detail=f"python={sys.version.split()[0]};timeout={args.timeout};audit_only={args.audit_only}",
        )
        temp_root = Path(tempfile.mkdtemp(prefix="sshfling-languages-"))
        canonical, version, entries = create_canonical_bundle(temp_root)
        canonical_files = set(file_inventory(canonical))
        evidence.record(
            "validator",
            "PASS",
            "canonical-runtime",
            status=0,
            detail=f"version={version};files={len(canonical_files)};requested={os.environ.get('SSHFLING_VERSION', '<unset>')}",
        )
        tested = 0
        blocked = 0
        audited = 0
        published = 0
        failed = 0
        blocked_tools: list[str] = []

        for language in selected:
            language_root = temp_root / language.identifier
            stage: Path | None = None
            work: Path | None = None
            outcome_recorded = False
            print(f"VALIDATE\t{language.identifier}\t{language.label}", flush=True)
            try:
                contract = validate_contract(language, canonical_files)
                evidence.record(language.identifier, "PASS", "structural-contract", status=0, detail=contract)
                stage, work = stage_language(temp_root, language, canonical, version)
                evidence.record(
                    language.identifier,
                    "PASS",
                    "canonical-bundle",
                    status=0,
                    detail=f"bundle={language.bundle};files={len(canonical_files)};version={version}",
                )
                published_archive = publish_source_archive(
                    stage,
                    language,
                    version,
                    work,
                    evidence,
                )
                published += 1
                if args.audit_only:
                    audited += 1
                    outcome_recorded = True
                    print(f"AUDITED\t{language.identifier}\tstructural=verified\ttested=no", flush=True)
                    evidence.record(language.identifier, "AUDITED", "outcome", status=0, detail="runtime_not_requested")
                    continue
                tools, missing = resolve_tools(language)
                if missing:
                    blocked += 1
                    blocked_tools.append(f"{language.identifier}:{','.join(missing)}")
                    outcome_recorded = True
                    print(
                        f"BLOCKED\t{language.identifier}\tmissing={','.join(missing)}\t"
                        "structural=verified\ttested=no",
                        flush=True,
                    )
                    evidence.record(
                        language.identifier,
                        "BLOCKED",
                        "outcome",
                        status="missing-toolchain",
                        detail=f"missing={','.join(missing)};structural=verified;tested=no",
                    )
                    continue
                if language.identifier not in NATIVE_RUNNERS:
                    blocked += 1
                    reason = "native-package-workflow-unavailable"
                    blocked_tools.append(f"{language.identifier}:{reason}")
                    outcome_recorded = True
                    print(
                        f"BLOCKED\t{language.identifier}\treason={reason}\t"
                        "structural=verified\ttested=no",
                        flush=True,
                    )
                    evidence.record(
                        language.identifier,
                        "BLOCKED",
                        "outcome",
                        status=reason,
                        detail="toolchain_present;structural=verified;tested=no",
                    )
                    continue
                runner = PackageRunner(
                    language,
                    stage,
                    work,
                    canonical,
                    version,
                    entries,
                    evidence,
                    args.timeout,
                    tools,
                    published_archive,
                )
                runner.run()
                tested += 1
                outcome_recorded = True
                print(
                    f"PASS\t{language.identifier}\tcommands={runner.command_count}\t"
                    "archive=yes\tinstall=yes\tconsumer=yes\tremove=yes",
                    flush=True,
                )
                evidence.record(
                    language.identifier,
                    "PASS",
                    "outcome",
                    status=0,
                    detail=f"commands={runner.command_count};archive=yes;install=yes;consumer=yes;remove=yes",
                )
            except (ValidationFailure, OSError, subprocess.SubprocessError, tarfile.TarError) as error:
                failed += 1
                outcome_recorded = True
                print(f"FAILED\t{language.identifier}\t{error}", file=sys.stderr, flush=True)
                evidence.record(language.identifier, "FAIL", "outcome", status=1, detail=str(error))
            finally:
                if language_root.exists():
                    shutil.rmtree(language_root)
                if evidence is not None:
                    evidence.record(
                        language.identifier,
                        "INFO",
                        "cleanup",
                        status=0,
                        detail=f"removed={language_root};outcome_recorded={outcome_recorded}",
                    )

        evidence.record(
            "validator",
            "PASS" if failed == 0 else "FAIL",
            "summary",
            status=0 if failed == 0 else 1,
            detail=f"tested={tested};blocked={blocked};audited={audited};published={published};"
            f"failed={failed};selected={len(selected)}",
        )
        print(
            f"SUMMARY\ttested={tested}\tblocked={blocked}\taudited={audited}\tpublished={published}\t"
            f"failed={failed}\t"
            f"evidence={evidence.path}",
            flush=True,
        )
        if blocked_tools:
            print(f"BLOCKED_TOOLS\t{';'.join(blocked_tools)}", flush=True)
        if failed:
            return 1
        if args.audit_only:
            return 0
        if blocked and not args.allow_blocked:
            return 3
        if tested == 0 and not (blocked and args.allow_blocked and published == len(selected)):
            print(
                "validator: no native package was tested; use --audit-only for a structural-only run",
                file=sys.stderr,
            )
            return 4
        return 0
    except (ValidationFailure, OSError, SyntaxError, csv.Error) as error:
        print(f"validator: {error}", file=sys.stderr)
        if evidence is not None:
            evidence.record("validator", "FAIL", "fatal", status=1, detail=str(error))
        return 1
    finally:
        if temp_root is not None and temp_root.exists():
            shutil.rmtree(temp_root)
            if evidence is not None:
                evidence.record("validator", "INFO", "final-cleanup", status=0, detail=f"removed={temp_root}")
        if lock_fd is not None:
            fcntl.flock(lock_fd, fcntl.LOCK_UN)
            os.close(lock_fd)


if __name__ == "__main__":
    raise SystemExit(main())
