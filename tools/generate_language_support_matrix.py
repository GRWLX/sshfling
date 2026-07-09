#!/usr/bin/env python3
"""Generate and validate SSHFling language/runtime support documentation.

The matrix is intentionally conservative: `PASS` means SSHFling has a tracked
source surface plus local release evidence for that language/runtime/config
class. Popular languages without a shipped SSHFling package or runtime adapter
remain explicit `UNSUPPORTED` rows instead of silent omissions.
"""

from __future__ import annotations

import argparse
from collections import Counter
from pathlib import Path
from typing import Iterable


REPO_ROOT = Path(__file__).resolve().parents[1]
DOC_PATH = REPO_ROOT / "docs" / "language-support.md"
TODO_PATH = REPO_ROOT / "TODO.txt"

BEGIN_MARKER = "<!-- BEGIN GENERATED LANGUAGE SUPPORT MATRIX -->"
END_MARKER = "<!-- END GENERATED LANGUAGE SUPPORT MATRIX -->"
TODO_BEGIN = "<!-- BEGIN GENERATED LANGUAGE SUPPORT CHECKLIST -->"
TODO_END = "<!-- END GENERATED LANGUAGE SUPPORT CHECKLIST -->"

ALLOWED_STATUSES = {
    "PASS",
    "BLOCKED",
    "FUTURE_WORK",
    "UNSUPPORTED",
    "NOT_APPLICABLE",
}

ORDERING_SOURCES = [
    {
        "name": "PYPL PopularitY of Programming Language Index",
        "url": "https://pypl.github.io/",
        "note": "Python-first search-interest signal, checked 2026-07-09.",
    },
    {
        "name": "TIOBE Index",
        "url": "https://www.tiobe.com/tiobe-index/",
        "note": "Monthly broad programming-language ranking signal, checked 2026-07-09.",
    },
    {
        "name": "GitHub Octoverse",
        "url": "https://octoverse.github.com/",
        "note": "Repository-activity signal; TypeScript is treated as top-tier.",
    },
    {
        "name": "Stack Overflow Developer Survey technology results",
        "url": "https://survey.stackoverflow.co/2025/technology",
        "note": "Developer-usage and sentiment signal, checked 2026-07-09.",
    },
]


def row(
    language: str,
    status: str,
    surface: str,
    evidence: str,
    rationale: str,
    category: str = "programming language",
) -> dict[str, str]:
    return {
        "language": language,
        "status": status,
        "category": category,
        "repo_surface": surface,
        "evidence": evidence,
        "rationale": rationale,
    }


PASS_PACKAGE_EVIDENCE = (
    "make test VERSION=0.1.16; make package-deb package-rpm package-dotnet "
    "package-java package-node package-python package-go package-rust package-php "
    "package-ruby package-native-libraries package-perl VERSION=0.1.16; "
    "GitHub release v0.1.16 artifacts"
)
PASS_PYTHON_EVIDENCE = (
    "make package-python VERSION=0.1.16; isolated pip and pipx install/import/CLI/uninstall "
    "validation in packaging/build-python.sh"
)
PASS_NODE_EVIDENCE = (
    "make test VERSION=0.1.16; make package-node VERSION=0.1.16; npm "
    "CommonJS/ESM import and run, strict TypeScript compile, bin, and uninstall validation"
)
PASS_JAVA_EVIDENCE = (
    "make package-java VERSION=0.1.16; Maven clean install, Gradle clean build, "
    "executable/source/Javadocs artifacts, and clean Maven/Gradle library consumers"
)
PASS_DOTNET_EVIDENCE = (
    "make package-dotnet VERSION=0.1.16; NuGet global tool plus SSHFling library pack, "
    "isolated tool install plus C#, Visual Basic, and F# PackageReference restore, API run, "
    "and removal validation"
)
PASS_NATIVE_EVIDENCE = (
    "make package-native-libraries VERSION=0.1.16; warning-clean C11/C++17 Ninja/Release "
    "and Make/Debug builds, ASan/UBSan CTest, CMake shared/static and pkg-config consumers, "
    "CLI smoke test, install/removal validation"
)
PASS_PERL_EVIDENCE = (
    "make package-perl VERSION=0.1.16; MakeMaker test/dist, archive inspection, isolated "
    "INSTALL_BASE module/CLI execution, init workflow, and removal validation"
)
PASS_GO_EVIDENCE = (
    "make package-go VERSION=0.1.16; go test/vet/install and archive validation in "
    "packaging/build-go.sh"
)
PASS_RUST_EVIDENCE = (
    "make package-rust VERSION=0.1.16; cargo fmt/test/clippy/package/install/uninstall and "
    "publish dry-run evidence"
)
PASS_PHP_EVIDENCE = (
    "make package-php VERSION=0.1.16; Composer validate/archive/install/autoload/CLI/remove "
    "validation in packaging/build-php.sh"
)
PASS_RUBY_EVIDENCE = (
    "make package-ruby VERSION=0.1.16; gem and Bundler install/CLI/uninstall validation in "
    "packaging/build-ruby.sh"
)
PASS_SCRIPT_EVIDENCE = (
    "make test VERSION=0.1.16; shell syntax checks through release validation; "
    "container production test"
)
UNSUPPORTED_EVIDENCE = (
    "git ls-files inventory and release matrix show no shipped SSHFling "
    "package/runtime implementation for this target"
)
FUTURE_EVIDENCE = (
    "cataloged as a possible expansion target; no supported SSHFling release "
    "artifact exists yet"
)
BLOCKED_WINDOWS_EVIDENCE = (
    "PowerShell files exist, but Windows runner/AuthentiCode/PowerShell "
    "validation evidence is unavailable in this Linux environment"
)


# Composite order: current broad popularity signals first, then long-tail
# languages, DSLs, hardware languages, shell variants, and config/markup
# surfaces. Status is repo evidence, not ranking.
LANGUAGE_SUPPORT: list[dict[str, str]] = [
    row(
        "Python",
        "PASS",
        "Primary CLI/runtime plus a universal Python wheel under packaging/python.",
        PASS_PYTHON_EVIDENCE,
        "Shipped and tested as SSHFling's primary implementation with pip and pipx installation.",
    ),
    row(
        "TypeScript",
        "PASS",
        "TypeScript declarations under packaging/node with npm package metadata.",
        PASS_NODE_EVIDENCE,
        "Shipped as typed npm package metadata for the Node.js CLI wrapper.",
    ),
    row(
        "JavaScript",
        "PASS",
        "Node.js CLI wrapper and CommonJS package surface under packaging/node.",
        PASS_NODE_EVIDENCE,
        "Shipped as an npm package that delegates to the bundled SSHFling Python CLI.",
    ),
    row(
        "Java",
        "PASS",
        "Public Java launcher library plus executable, sources, and Javadocs artifacts built with Maven and Gradle.",
        PASS_JAVA_EVIDENCE,
        "Shipped with clean Maven and Gradle consumer projects that invoke SSHFling.run.",
    ),
    row(
        "C",
        "PASS",
        "POSIX C11 shared/static launcher libraries, public header, CLI, CMake exports, and pkg-config metadata under packaging/native.",
        PASS_NATIVE_EVIDENCE,
        "Shipped as source with clean shared, static, CMake, pkg-config, CLI, and install consumers.",
    ),
    row(
        "C++",
        "PASS",
        "C++17 header wrapper over the native C ABI with an exported CMake target and clean consumer.",
        PASS_NATIVE_EVIDENCE,
        "Shipped as a typed C++ wrapper and validated through a clean static-library CMake consumer.",
    ),
    row(
        "C#/.NET",
        "PASS",
        "Cross-platform NuGet library and .NET global tool under packaging/dotnet.",
        PASS_DOTNET_EVIDENCE,
        "Shipped as separate importable library and command packages with clean consumer validation.",
    ),
    row(
        "SQL",
        "UNSUPPORTED",
        "No database extension, migration package, CLI SQL interface, or supported schema runtime.",
        UNSUPPORTED_EVIDENCE,
        "SSHFling does not expose a database language surface.",
    ),
    row(
        "Go",
        "PASS",
        "Go module and importable launcher API under packaging/go with an installable CLI command.",
        PASS_GO_EVIDENCE,
        "Shipped as a source module archive that embeds the SSHFling Python runtime and templates.",
    ),
    row(
        "Rust",
        "PASS",
        "Rust library and CLI crate under packaging/rust with bundled runtime resources.",
        PASS_RUST_EVIDENCE,
        "Shipped as a Cargo crate and validated through package, install, and publish dry-run flows.",
    ),
    row(
        "PHP",
        "PASS",
        "PSR-4 Composer library and CLI wrapper under packaging/php.",
        PASS_PHP_EVIDENCE,
        "Shipped as a Composer artifact package with clean install and removal evidence.",
    ),
    row(
        "Shell/POSIX sh",
        "PASS",
        "Installer, packaging, and validation scripts use POSIX-compatible shell where required.",
        PASS_SCRIPT_EVIDENCE,
        "Tracked shell scripts are part of supported packaging and validation flows.",
        "shell",
    ),
    row(
        "Bash",
        "PASS",
        "Release, packaging, container, and test scripts use Bash explicitly where needed.",
        PASS_SCRIPT_EVIDENCE,
        "Tracked Bash scripts are tested by release and container validation.",
        "shell",
    ),
    row(
        "PowerShell",
        "BLOCKED",
        "Cross-OS validation scripts include PowerShell, but full Windows runtime/package proof is absent.",
        BLOCKED_WINDOWS_EVIDENCE,
        "Cannot mark PASS until Windows/PowerShell execution and signing evidence exists.",
        "shell",
    ),
    row("Kotlin", "UNSUPPORTED", "No Kotlin/JVM package or source.", UNSUPPORTED_EVIDENCE, "No supported Kotlin surface is shipped."),
    row("Swift", "UNSUPPORTED", "No Swift package, source, or Apple native API wrapper.", UNSUPPORTED_EVIDENCE, "No supported Swift surface is shipped."),
    row("R", "FUTURE_WORK", "No R package, R source, or CRAN-style release path.", FUTURE_EVIDENCE, "Data-science package support would need a new package surface."),
    row(
        "Ruby",
        "PASS",
        "Ruby library and executable gem under packaging/ruby.",
        PASS_RUBY_EVIDENCE,
        "Shipped as a RubyGem and validated with both RubyGems and Bundler.",
    ),
    row("Dart", "UNSUPPORTED", "No Dart package, pubspec, Flutter plugin, or Dart source.", UNSUPPORTED_EVIDENCE, "No supported Dart surface is shipped."),
    row("Lua", "UNSUPPORTED", "No Lua module, luarocks package, or Lua source.", UNSUPPORTED_EVIDENCE, "No supported Lua surface is shipped."),
    row(
        "Perl",
        "PASS",
        "Perl module and executable with ExtUtils::MakeMaker metadata under packaging/perl.",
        PASS_PERL_EVIDENCE,
        "Shipped as a CPAN-style source distribution with isolated module and CLI validation.",
    ),
    row("Scala", "UNSUPPORTED", "No Scala/SBT package or Scala source.", UNSUPPORTED_EVIDENCE, "No supported Scala surface is shipped."),
    row(
        "Visual Basic/.NET",
        "PASS",
        "Visual Basic consumer project references the SSHFling NuGet library and invokes SSHFlingRunner.",
        PASS_DOTNET_EVIDENCE,
        "The language consumes the shipped .NET library through a clean local NuGet restore and runtime workflow.",
    ),
    row("MATLAB", "UNSUPPORTED", "No MATLAB toolbox, M files, or mex interface.", UNSUPPORTED_EVIDENCE, "No supported MATLAB package is shipped."),
    row("Objective-C", "UNSUPPORTED", "No Objective-C source, framework, or Cocoa package surface.", UNSUPPORTED_EVIDENCE, "No supported Objective-C surface is shipped."),
    row("Groovy", "UNSUPPORTED", "No Groovy source, Gradle plugin, or Maven artifact for Groovy.", UNSUPPORTED_EVIDENCE, "No supported Groovy surface is shipped."),
    row("Delphi/Object Pascal", "UNSUPPORTED", "No Pascal source or package surface.", UNSUPPORTED_EVIDENCE, "No supported Pascal surface is shipped."),
    row("Julia", "UNSUPPORTED", "No Julia package, Project.toml, or Julia source.", UNSUPPORTED_EVIDENCE, "No supported Julia package is shipped."),
    row("HCL/Terraform", "UNSUPPORTED", "No Terraform provider, module, or HCL API surface.", UNSUPPORTED_EVIDENCE, "No supported Terraform provider/module is shipped.", "infrastructure DSL"),
    row("Assembly", "UNSUPPORTED", "No assembly source or architecture-specific runtime.", UNSUPPORTED_EVIDENCE, "No supported assembly surface is shipped."),
    row("COBOL", "UNSUPPORTED", "No COBOL source or package surface.", UNSUPPORTED_EVIDENCE, "No supported COBOL surface is shipped."),
    row("Fortran", "UNSUPPORTED", "No Fortran source or package surface.", UNSUPPORTED_EVIDENCE, "No supported Fortran surface is shipped."),
    row("SAS", "UNSUPPORTED", "No SAS package or scripts.", UNSUPPORTED_EVIDENCE, "No supported SAS surface is shipped."),
    row("ABAP", "UNSUPPORTED", "No ABAP transport, source, or SAP package.", UNSUPPORTED_EVIDENCE, "No supported ABAP surface is shipped."),
    row("Apex", "UNSUPPORTED", "No Salesforce package, Apex source, or SFDX project.", UNSUPPORTED_EVIDENCE, "No supported Apex surface is shipped."),
    row("PL/SQL", "UNSUPPORTED", "No Oracle package or PL/SQL scripts.", UNSUPPORTED_EVIDENCE, "No supported PL/SQL surface is shipped."),
    row("T-SQL", "UNSUPPORTED", "No SQL Server package or T-SQL scripts.", UNSUPPORTED_EVIDENCE, "No supported T-SQL surface is shipped."),
    row("Elixir", "UNSUPPORTED", "No Mix project, Elixir source, or Hex package.", UNSUPPORTED_EVIDENCE, "No supported Elixir surface is shipped."),
    row("Erlang", "UNSUPPORTED", "No Erlang application, rebar config, or Hex package.", UNSUPPORTED_EVIDENCE, "No supported Erlang surface is shipped."),
    row("Haskell", "UNSUPPORTED", "No Cabal/Stack project or Haskell source.", UNSUPPORTED_EVIDENCE, "No supported Haskell surface is shipped."),
    row("Clojure", "UNSUPPORTED", "No deps.edn/Leiningen project or Clojure source.", UNSUPPORTED_EVIDENCE, "No supported Clojure surface is shipped."),
    row(
        "F#",
        "PASS",
        "F# consumer project references the SSHFling NuGet library and invokes SSHFlingRunner.",
        PASS_DOTNET_EVIDENCE,
        "The language consumes the shipped .NET library through a clean local NuGet restore and runtime workflow.",
    ),
    row("OCaml", "UNSUPPORTED", "No dune/opam package or OCaml source.", UNSUPPORTED_EVIDENCE, "No supported OCaml surface is shipped."),
    row("Zig", "UNSUPPORTED", "No Zig source or build.zig.", UNSUPPORTED_EVIDENCE, "No supported Zig surface is shipped."),
    row("Nim", "UNSUPPORTED", "No Nim source or nimble package.", UNSUPPORTED_EVIDENCE, "No supported Nim surface is shipped."),
    row("Crystal", "UNSUPPORTED", "No Crystal source or shard.yml.", UNSUPPORTED_EVIDENCE, "No supported Crystal surface is shipped."),
    row("D", "FUTURE_WORK", "No D source, dub package, or binary artifact.", FUTURE_EVIDENCE, "Native D support would need a new package surface."),
    row("V", "FUTURE_WORK", "No V source or package manifest.", FUTURE_EVIDENCE, "Native V support would need a new package surface."),
    row("Ada", "UNSUPPORTED", "No Ada project or source.", UNSUPPORTED_EVIDENCE, "No supported Ada surface is shipped."),
    row("Common Lisp", "UNSUPPORTED", "No ASDF system or Lisp source.", UNSUPPORTED_EVIDENCE, "No supported Common Lisp surface is shipped."),
    row("Scheme/Racket", "UNSUPPORTED", "No Scheme/Racket package or source.", UNSUPPORTED_EVIDENCE, "No supported Scheme or Racket surface is shipped."),
    row("Prolog", "UNSUPPORTED", "No Prolog package or source.", UNSUPPORTED_EVIDENCE, "No supported Prolog surface is shipped."),
    row("Smalltalk", "UNSUPPORTED", "No Smalltalk package or source.", UNSUPPORTED_EVIDENCE, "No supported Smalltalk surface is shipped."),
    row("Tcl", "UNSUPPORTED", "No Tcl package or source.", UNSUPPORTED_EVIDENCE, "No supported Tcl surface is shipped."),
    row("AWK", "UNSUPPORTED", "No supported AWK scripts or CLI contract.", UNSUPPORTED_EVIDENCE, "AWK is not a shipped SSHFling language surface.", "shell"),
    row("sed", "UNSUPPORTED", "No supported sed script package or CLI contract.", UNSUPPORTED_EVIDENCE, "sed is not a shipped SSHFling language surface.", "shell"),
    row("Zsh", "FUTURE_WORK", "No Zsh completion/runtime test or Zsh package surface.", FUTURE_EVIDENCE, "Shell integration can be added later with tests.", "shell"),
    row("Fish", "FUTURE_WORK", "No Fish completion/runtime test or Fish package surface.", FUTURE_EVIDENCE, "Shell integration can be added later with tests.", "shell"),
    row("Nix", "PASS", "Generated Nix package metadata exists and is covered by cross-OS validation scope.", "docs/build-targets.md; cross-os validation workflow scope; release package site verifier", "Nix is supported as packaging metadata, not as a product runtime API.", "package DSL"),
    row("Guix Scheme", "UNSUPPORTED", "Generated Guix metadata exists, but no Guix runtime/API or Scheme package support is claimed.", UNSUPPORTED_EVIDENCE, "Packaging metadata does not equal language runtime support.", "package DSL"),
    row("Solidity", "UNSUPPORTED", "No smart contract package or Solidity source.", UNSUPPORTED_EVIDENCE, "No supported Solidity surface is shipped."),
    row("Vyper", "UNSUPPORTED", "No smart contract package or Vyper source.", UNSUPPORTED_EVIDENCE, "No supported Vyper surface is shipped."),
    row("Move", "UNSUPPORTED", "No Move package or source.", UNSUPPORTED_EVIDENCE, "No supported Move surface is shipped."),
    row("WebAssembly/WASI", "UNSUPPORTED", "No WASM module, WIT interface, or WASI package.", UNSUPPORTED_EVIDENCE, "No supported WebAssembly/WASI artifact is shipped."),
    row("Elm", "UNSUPPORTED", "No Elm package or source.", UNSUPPORTED_EVIDENCE, "No supported Elm surface is shipped."),
    row("PureScript", "UNSUPPORTED", "No PureScript package or source.", UNSUPPORTED_EVIDENCE, "No supported PureScript surface is shipped."),
    row("Reason/ReScript", "UNSUPPORTED", "No Reason/ReScript package or source.", UNSUPPORTED_EVIDENCE, "No supported Reason/ReScript surface is shipped."),
    row("Forth", "UNSUPPORTED", "No Forth package or source.", UNSUPPORTED_EVIDENCE, "No supported Forth surface is shipped."),
    row("APL", "UNSUPPORTED", "No APL package or source.", UNSUPPORTED_EVIDENCE, "No supported APL surface is shipped."),
    row("J", "UNSUPPORTED", "No J package or source.", UNSUPPORTED_EVIDENCE, "No supported J surface is shipped."),
    row("LabVIEW G", "UNSUPPORTED", "No LabVIEW project or package.", UNSUPPORTED_EVIDENCE, "No supported LabVIEW surface is shipped."),
    row("Scratch", "UNSUPPORTED", "No Scratch project or extension.", UNSUPPORTED_EVIDENCE, "No supported Scratch surface is shipped."),
    row("Q/KDB+", "UNSUPPORTED", "No Q package or KDB+ integration.", UNSUPPORTED_EVIDENCE, "No supported Q/KDB+ surface is shipped."),
    row("Hack", "UNSUPPORTED", "No Hack package or source.", UNSUPPORTED_EVIDENCE, "No supported Hack surface is shipped."),
    row("CFML", "UNSUPPORTED", "No CFML package or source.", UNSUPPORTED_EVIDENCE, "No supported CFML surface is shipped."),
    row("Wolfram Language", "UNSUPPORTED", "No Wolfram package or notebook integration.", UNSUPPORTED_EVIDENCE, "No supported Wolfram Language surface is shipped."),
    row("Verilog", "UNSUPPORTED", "No HDL source, FPGA bitstream, or vendor flow.", UNSUPPORTED_EVIDENCE, "No FPGA fabric support is shipped; host OS support is tracked separately.", "hardware description language"),
    row("VHDL", "UNSUPPORTED", "No HDL source, FPGA bitstream, or vendor flow.", UNSUPPORTED_EVIDENCE, "No FPGA fabric support is shipped; host OS support is tracked separately.", "hardware description language"),
    row("SystemVerilog", "UNSUPPORTED", "No HDL source, FPGA bitstream, or vendor flow.", UNSUPPORTED_EVIDENCE, "No FPGA fabric support is shipped; host OS support is tracked separately.", "hardware description language"),
    row("CUDA", "UNSUPPORTED", "No CUDA kernels or GPU package.", UNSUPPORTED_EVIDENCE, "No supported CUDA surface is shipped."),
    row("OpenCL C", "UNSUPPORTED", "No OpenCL kernels or runtime package.", UNSUPPORTED_EVIDENCE, "No supported OpenCL surface is shipped."),
    row("GLSL", "UNSUPPORTED", "No shader package or graphics runtime.", UNSUPPORTED_EVIDENCE, "No supported GLSL surface is shipped."),
    row("HLSL", "UNSUPPORTED", "No shader package or graphics runtime.", UNSUPPORTED_EVIDENCE, "No supported HLSL surface is shipped."),
    row("WGSL", "UNSUPPORTED", "No WebGPU shader package or graphics runtime.", UNSUPPORTED_EVIDENCE, "No supported WGSL surface is shipped."),
    row("Chapel", "UNSUPPORTED", "No Chapel source or package.", UNSUPPORTED_EVIDENCE, "No supported Chapel surface is shipped."),
    row("Pony", "UNSUPPORTED", "No Pony source or package.", UNSUPPORTED_EVIDENCE, "No supported Pony surface is shipped."),
    row("Janet", "UNSUPPORTED", "No Janet source or package.", UNSUPPORTED_EVIDENCE, "No supported Janet surface is shipped."),
    row("Odin", "UNSUPPORTED", "No Odin source or package.", UNSUPPORTED_EVIDENCE, "No supported Odin surface is shipped."),
    row("Ballerina", "UNSUPPORTED", "No Ballerina package or source.", UNSUPPORTED_EVIDENCE, "No supported Ballerina surface is shipped."),
    row("Gleam", "UNSUPPORTED", "No Gleam package or source.", UNSUPPORTED_EVIDENCE, "No supported Gleam surface is shipped."),
    row("Roc", "UNSUPPORTED", "No Roc package or source.", UNSUPPORTED_EVIDENCE, "No supported Roc surface is shipped."),
    row("Red", "UNSUPPORTED", "No Red package or source.", UNSUPPORTED_EVIDENCE, "No supported Red surface is shipped."),
    row("Ring", "UNSUPPORTED", "No Ring package or source.", UNSUPPORTED_EVIDENCE, "No supported Ring surface is shipped."),
    row("Harbour", "UNSUPPORTED", "No Harbour package or source.", UNSUPPORTED_EVIDENCE, "No supported Harbour surface is shipped."),
    row("Xojo", "UNSUPPORTED", "No Xojo project or package.", UNSUPPORTED_EVIDENCE, "No supported Xojo surface is shipped."),
    row("AutoHotkey", "UNSUPPORTED", "No AutoHotkey scripts or package.", UNSUPPORTED_EVIDENCE, "No supported AutoHotkey surface is shipped.", "automation language"),
    row("AutoIt", "UNSUPPORTED", "No AutoIt scripts or package.", UNSUPPORTED_EVIDENCE, "No supported AutoIt surface is shipped.", "automation language"),
    row("AppleScript", "UNSUPPORTED", "No AppleScript package or source.", UNSUPPORTED_EVIDENCE, "No supported AppleScript surface is shipped.", "automation language"),
    row("VBScript", "UNSUPPORTED", "No VBScript package or source.", UNSUPPORTED_EVIDENCE, "No supported VBScript surface is shipped.", "automation language"),
    row("Power Query M", "UNSUPPORTED", "No Power Query connector or M source.", UNSUPPORTED_EVIDENCE, "No supported Power Query surface is shipped."),
    row("Q#", "UNSUPPORTED", "No Q# package or source.", UNSUPPORTED_EVIDENCE, "No supported Q# surface is shipped."),
    row("Arduino/Wiring", "UNSUPPORTED", "No Arduino library, sketch, or PlatformIO package.", UNSUPPORTED_EVIDENCE, "No supported Arduino/Wiring surface is shipped."),
    row("MicroPython", "UNSUPPORTED", "No MicroPython firmware package or module.", UNSUPPORTED_EVIDENCE, "No supported MicroPython surface is shipped."),
    row("CircuitPython", "UNSUPPORTED", "No CircuitPython library package.", UNSUPPORTED_EVIDENCE, "No supported CircuitPython surface is shipped."),
    row("Elvish", "UNSUPPORTED", "No Elvish shell integration or package.", UNSUPPORTED_EVIDENCE, "No supported Elvish surface is shipped.", "shell"),
    row("Nushell", "UNSUPPORTED", "No Nushell integration or package.", UNSUPPORTED_EVIDENCE, "No supported Nushell surface is shipped.", "shell"),
    row(
        "CMake",
        "PASS",
        "Native C/C++ project exports versioned SSHFling CMake package targets for shared and static linking.",
        PASS_NATIVE_EVIDENCE,
        "Clean external C and C++ projects resolve the installed package with find_package(SSHFling CONFIG REQUIRED).",
        "build DSL",
    ),
    row("Make",
        "PASS",
        "Top-level Makefile drives release validation and package targets.",
        "make test VERSION=0.1.16; package build commands; release readiness commands",
        "Make is a supported build orchestration surface for maintainers.",
        "build DSL",
    ),
    row(
        "Dockerfile",
        "PASS",
        "Tracked Dockerfiles build production and test container images.",
        "docker build -f tests/docker/Dockerfile.production -t sshfling-production-test:0.1.16 .; docker run --rm sshfling-production-test:0.1.16",
        "Dockerfile surfaces are part of validated container testing.",
        "container DSL",
    ),
    row(
        "YAML/JSON schema",
        "PASS",
        "GitHub Actions workflows, package manifests, scanner outputs, and release matrix data.",
        "workflow static checks; release matrix validation; git diff --check",
        "Tracked YAML/JSON configuration surfaces are validated by release tooling.",
        "configuration",
    ),
    row(
        "XML/POM",
        "PASS",
        "Java Maven POM metadata under packaging/java.",
        PASS_PACKAGE_EVIDENCE,
        "The Maven POM is part of shipped Java package evidence.",
        "configuration",
    ),
    row(
        "TOML",
        "PASS",
        "Project-local Codex config uses TOML and is documented as agent concurrency policy.",
        "docs/codex-enterprise-workflow.md; .codex/config.toml retained as local policy input",
        "TOML is tracked as local operational configuration, not product runtime API.",
        "configuration",
    ),
    row(
        "Markdown",
        "PASS",
        "Tracked docs, release checklist, threat model, install/uninstall, and wiki source.",
        "git diff --check; docs reviewed in release readiness work",
        "Markdown is the supported human-readable documentation format.",
        "documentation",
    ),
    row("HTML/CSS", "UNSUPPORTED", "No tracked static site source, CSS package, or browser UI runtime.", UNSUPPORTED_EVIDENCE, "Generated package web output is not a supported HTML/CSS app surface.", "markup/style"),
    row("Svelte", "UNSUPPORTED", "No Svelte package or source.", UNSUPPORTED_EVIDENCE, "No supported Svelte surface is shipped.", "framework"),
    row("Vue", "UNSUPPORTED", "No Vue package or source.", UNSUPPORTED_EVIDENCE, "No supported Vue surface is shipped.", "framework"),
    row("React/JSX", "UNSUPPORTED", "No React package or JSX/TSX source.", UNSUPPORTED_EVIDENCE, "No supported React surface is shipped.", "framework"),
    row("Angular", "UNSUPPORTED", "No Angular workspace or package.", UNSUPPORTED_EVIDENCE, "No supported Angular surface is shipped.", "framework"),
]


def validate_language_support(entries: Iterable[dict[str, str]] = LANGUAGE_SUPPORT) -> list[str]:
    errors: list[str] = []
    seen: set[str] = set()
    entries = list(entries)

    if not entries:
        errors.append("language support matrix must not be empty")
        return errors

    if entries[0]["language"] != "Python":
        errors.append("Python must remain first in the composite ordering")

    names = [entry["language"] for entry in entries]
    for required in (
        "TypeScript",
        "JavaScript",
        "Java",
        "C",
        "C++",
        "C#/.NET",
        "Visual Basic/.NET",
        "F#",
        "Perl",
        "CMake",
    ):
        if required not in names:
            errors.append(f"missing required language row: {required}")

    for entry in entries:
        language = entry.get("language", "")
        if not language:
            errors.append("language row is missing language")
            continue
        if language in seen:
            errors.append(f"duplicate language row: {language}")
        seen.add(language)

        status = entry.get("status", "")
        if status not in ALLOWED_STATUSES:
            errors.append(f"{language}: unsupported status {status!r}")

        for field in ("category", "repo_surface", "evidence", "rationale"):
            if not entry.get(field):
                errors.append(f"{language}: missing {field}")

        if status == "PASS" and (
            "No " in entry.get("repo_surface", "") or "unsupported" in entry.get("rationale", "").lower()
        ):
            errors.append(f"{language}: PASS row has unsupported/no-surface wording")

    return errors


def status_counts(entries: Iterable[dict[str, str]] = LANGUAGE_SUPPORT) -> Counter[str]:
    return Counter(entry["status"] for entry in entries)


def markdown_table(entries: Iterable[dict[str, str]]) -> str:
    lines = [
        "| Order | Language / surface | Category | Status | Repo surface | Evidence | Rationale |",
        "| ---: | --- | --- | --- | --- | --- | --- |",
    ]
    for index, entry in enumerate(entries, start=1):
        lines.append(
            "| {order} | {language} | {category} | {status} | {surface} | {evidence} | {rationale} |".format(
                order=index,
                language=escape_table(entry["language"]),
                category=escape_table(entry["category"]),
                status=entry["status"],
                surface=escape_table(entry["repo_surface"]),
                evidence=escape_table(entry["evidence"]),
                rationale=escape_table(entry["rationale"]),
            )
        )
    return "\n".join(lines)


def escape_table(value: str) -> str:
    return value.replace("|", "\\|").replace("\n", " ")


def render_markdown(entries: Iterable[dict[str, str]] = LANGUAGE_SUPPORT) -> str:
    entries = list(entries)
    counts = status_counts(entries)
    source_lines = "\n".join(
        f"- [{source['name']}]({source['url']}): {source['note']}"
        for source in ORDERING_SOURCES
    )
    status_summary = ", ".join(
        f"{status}: {counts.get(status, 0)}"
        for status in ("PASS", "BLOCKED", "FUTURE_WORK", "UNSUPPORTED", "NOT_APPLICABLE")
    )
    return "\n".join(
        [
            "# SSHFling Language Support Matrix",
            "",
            "This file is generated from `tools/generate_language_support_matrix.py`.",
            "It orders language, runtime, shell, DSL, and configuration surfaces by",
            "a conservative composite of current public usage signals first, then",
            "long-tail and specialized targets. A high ranking does not create a",
            "support claim. `PASS` requires tracked SSHFling source plus release",
            "evidence; otherwise the row remains `BLOCKED`, `FUTURE_WORK`, or",
            "`UNSUPPORTED`.",
            "",
            "Ordering sources:",
            "",
            source_lines,
            "",
            f"Status summary: {status_summary}.",
            "",
            "OS-native command-language policy: Python remains the primary",
            "SSHFling CLI implementation and release-tooling language, but",
            "host OS execution paths should use the target OS command language",
            "where practical: POSIX sh/Bash for Unix-like hosts and PowerShell",
            "for Windows. Python one-liners should not be used as a substitute",
            "for native shell behavior in forced-command wrappers, package",
            "maintainer scripts, or cross-OS command execution tests.",
            "",
            BEGIN_MARKER,
            "",
            markdown_table(entries),
            "",
            END_MARKER,
            "",
            "Generated docs are tracked because this compact matrix is a source",
            "declaration. Massive per-OS/per-language release evidence remains",
            "ignored under `docs/release/enterprise-release-evidence/`, `build/`,",
            "`dist/`, `package-dist/`, or `release-dist/`.",
            "",
        ]
    )


def todo_line(index: int, entry: dict[str, str]) -> str:
    checked = "x" if entry["status"] == "PASS" else " "
    detail_key = "blocker" if entry["status"] == "BLOCKED" else "reason"
    detail = entry["rationale"] if entry["status"] != "PASS" else entry["evidence"]
    return (
        f"- [{checked}] {index:03d}. {entry['language']}. - status: {entry['status']}; "
        f"category: {entry['category']}; {detail_key}: {detail}; "
        f"surface: {entry['repo_surface']}; evidence: {entry['evidence']}; "
        "owner: language-matrix-generator"
    )


def render_todo_checklist(entries: Iterable[dict[str, str]] = LANGUAGE_SUPPORT) -> str:
    entries = list(entries)
    counts = status_counts(entries)
    lines = [
        TODO_BEGIN,
        "",
        "## Top Language Ordering",
        "",
        "Generated ordered language/runtime checklist. The order starts with current broad",
        "usage signals, then continues through long-tail programming, shell, hardware,",
        "automation, package DSL, configuration, and markup surfaces. `PASS` means",
        "repo-local SSHFling evidence exists; high-usage unsupported languages remain",
        "explicitly unchecked.",
        "",
        (
            f"Summary: total {len(entries)}; PASS {counts.get('PASS', 0)}; "
            f"BLOCKED {counts.get('BLOCKED', 0)}; FUTURE_WORK {counts.get('FUTURE_WORK', 0)}; "
            f"UNSUPPORTED {counts.get('UNSUPPORTED', 0)}; NOT_APPLICABLE {counts.get('NOT_APPLICABLE', 0)}."
        ),
        "",
    ]
    lines.extend(todo_line(index, entry) for index, entry in enumerate(entries, start=1))
    lines.extend(
        [
            "",
            "## All Language Catalog",
            "",
            "The all-language catalog is the same ordered matrix rendered as a compact table.",
            "",
            markdown_table(entries),
            "",
            TODO_END,
        ]
    )
    return "\n".join(lines)


def replace_between(text: str, start: str, end: str, replacement: str) -> str:
    start_index = text.find(start)
    end_index = text.find(end)
    if start_index != -1 and end_index != -1 and end_index > start_index:
        return text[:start_index] + replacement + text[end_index + len(end) :]
    return text.rstrip() + "\n\n" + replacement + "\n"


def update_legacy_todo(todo_path: Path = TODO_PATH) -> None:
    if not todo_path.exists():
        return
    text = todo_path.read_text(encoding="utf-8")
    generated = render_todo_checklist()
    if TODO_BEGIN in text and TODO_END in text:
        todo_path.write_text(replace_between(text, TODO_BEGIN, TODO_END, generated), encoding="utf-8")
        return

    top = text.find("## Top Language Ordering")
    runtime = text.find("## Per-Language Runtime Checks")
    if top != -1 and runtime != -1 and runtime > top:
        updated = text[:top] + generated + "\n\n" + text[runtime:]
        todo_path.write_text(updated, encoding="utf-8")
        return

    todo_path.write_text(text.rstrip() + "\n\n" + generated + "\n", encoding="utf-8")


def write_markdown(path: Path = DOC_PATH) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(render_markdown(), encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="write docs/language-support.md")
    parser.add_argument("--update-todo", action="store_true", help="update ignored TODO.txt language sections")
    parser.add_argument("--check", action="store_true", help="validate generated docs are current")
    args = parser.parse_args(argv)

    errors = validate_language_support()
    if errors:
        for error in errors:
            print(error)
        return 1

    rendered = render_markdown()

    if args.write:
        write_markdown()
    if args.update_todo:
        update_legacy_todo()
    if args.check:
        if not DOC_PATH.exists():
            print(f"missing {DOC_PATH.relative_to(REPO_ROOT)}")
            return 1
        current = DOC_PATH.read_text(encoding="utf-8")
        if current != rendered:
            print(f"{DOC_PATH.relative_to(REPO_ROOT)} is not current; run tools/generate_language_support_matrix.py --write")
            return 1

    if not args.write and not args.check and not args.update_todo:
        print(rendered)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
