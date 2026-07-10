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
PASS_FUNCTIONAL_EVIDENCE = (
    "./packaging/build-functional-languages.sh --allow-blocked --language haskell"
)
PASS_NODE_EVIDENCE = (
    "make test VERSION=0.1.16; make package-node VERSION=0.1.16; npm "
    "CommonJS/ESM import and run, strict TypeScript compile, bin, and uninstall validation"
)
PASS_WEB_CONSUMER_EVIDENCE = (
    "make package-web-language-consumers VERSION=0.1.16; clean npm installation from the "
    "packed SSHFling artifact, language/framework compilation, trusted Node-side API execution, "
    "template discovery, and generated-output assertions"
)
PASS_DART_EVIDENCE = (
    "make package-dart-consumer VERSION=0.1.16; Dart SDK 3.12.2 resolves the packed npm "
    "library offline, enforces dart format and dart analyze, compiles the typed adapter to a "
    "native executable, and validates the trusted Node bridge execution"
)
PASS_CFML_EVIDENCE = (
    "make package-node VERSION=0.1.16; SSHFLING_NPM_PACKAGE=dist/sshfling-0.1.16.tgz "
    "bash packaging/build-web-language-consumers.sh cfml; CommandBox 6.3.3 executes the "
    "CFML template after the Node bridge validates the packed SSHFling API"
)
BLOCKED_WEB_TOOLCHAIN_EVIDENCE = (
    "tracked package/source and a passing SSHFling Node bridge exist under packaging/node/consumers, "
    "but the required external language runtime is unavailable on the validation host"
)
PASS_FUNCTIONAL_LANGUAGES_EVIDENCE = (
    "bash packaging/build-functional-languages.sh --allow-blocked; "
    "dist/sshfling-functional-languages-0.1.16-validation.tsv"
)
PASS_SYSTEM_LANGUAGES_EVIDENCE = (
    "bash packaging/build-systems-languages.sh --allow-blocked; "
    "dist/sshfling-systems-languages-0.1.16-validation.tsv"
)
PASS_SWIFT_EVIDENCE = (
    "GitHub Actions Language runtime validation run "
    "https://github.com/GRWLX/sshfling/actions/runs/29072584483 on commit "
    "8b52008f49d3d256cee5d3c0fbfed2b9d1fa5607; the ubuntu-24.04 strict catalog "
    "records RUNTIME swift PASS and exact SwiftPM archive-lifecycle evidence in "
    "dist/sshfling-systems-languages-0.1.16-validation.tsv"
)
BLOCKED_TOOLCHAIN_EVIDENCE = (
    "tracked package/source and a validated SSHFling surface are present under the language directory, "
    "but the required external runtime/toolchain is unavailable on the validation host"
)
PASS_JAVA_EVIDENCE = (
    "make package-java VERSION=0.1.16; Maven clean install, Gradle clean build, "
    "executable/source/Javadocs artifacts, and clean Java, Kotlin, Scala, and Groovy consumers"
)
PASS_JVM_CONSUMER_EVIDENCE = (
    "make package-java VERSION=0.1.16; pinned Maven and Gradle compiler/build metadata, "
    "clean language-specific compilation at JVM 11, SSHFling.run API execution, init workflow, "
    "and published JAR/POM consumer validation"
)
PASS_CLOJURE_EVIDENCE = (
    "make package-java VERSION=0.1.16; pinned Clojure 1.12 Maven and Gradle projects, "
    "packaged namespace checks, isolated SSHFling dependency resolution, public Java API "
    "execution, exact version output, and init workflow validation"
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
PASS_SCRIPTING_LANGUAGE_EVIDENCE = (
    "make package-scripting-languages VERSION=0.1.16; versioned archive build, isolated "
    "source/library import, canonical CLI execution, init asset verification, and removal "
    "evidence in packaging/build-scripting-languages.sh"
)
BLOCKED_SCRIPTING_LANGUAGE_EVIDENCE = (
    "tracked package and language source exist under packaging/shell-languages or "
    "packaging/guix-scheme, but packaging/build-scripting-languages.sh records the required "
    "language/package runtime as SKIP on the validation host"
)
UNSUPPORTED_EVIDENCE = (
    "git ls-files inventory and release matrix show no shipped SSHFling "
    "package/runtime implementation for this target"
)
FUTURE_EVIDENCE = (
    "cataloged as a possible expansion target; no supported SSHFling release "
    "artifact exists yet"
)
DOMAIN_AUDIT_EVIDENCE = (
    "bash packaging/build-domain-languages.sh audit; packaging/domain-languages/manifest.tsv; "
    "docs/language-external-blockers.md"
)


def domain_blocked(
    language: str,
    surface: str,
    rationale: str,
    category: str = "programming language",
) -> dict[str, str]:
    return row(language, "BLOCKED", surface, DOMAIN_AUDIT_EVIDENCE, rationale, category)


def domain_not_applicable(
    language: str,
    rationale: str,
    category: str = "programming language",
) -> dict[str, str]:
    return row(
        language,
        "NOT_APPLICABLE",
        "The domain-language audit records an explicit semantic boundary and intentionally ships no launcher.",
        DOMAIN_AUDIT_EVIDENCE,
        rationale,
        category,
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
    domain_not_applicable(
        "SQL",
        "Standard SQL has no portable process API, and SSHFling exposes no database schema or protocol.",
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
        "PASS",
        "PowerShell 7 module, manifest, native script CLI, POSIX CLI, runtime, and templates under packaging/shell-languages/powershell.",
        PASS_SCRIPTING_LANGUAGE_EVIDENCE,
        "PowerShell executes the module and native CLI workflows; Windows MSI and signing evidence remains a separate platform concern.",
        "shell",
    ),
    row(
        "Kotlin",
        "PASS",
        "Kotlin 2.4 Maven and Gradle consumers compile against the published SSHFling Java library.",
        PASS_JVM_CONSUMER_EVIDENCE,
        "The clean Kotlin application invokes SSHFling.run and validates the bundled runtime workflow.",
    ),
    row(
        "Swift",
        "PASS",
        "SwiftPM package metadata, library sources, executable, and external consumer are tracked under packaging/systems-languages/swift.",
        PASS_SWIFT_EVIDENCE,
        "Ubuntu 24.04 hosted validation extracts the versioned source archive into an isolated prefix, executes the local-path SwiftPM consumer and CLI workflows, and verifies removal.",
    ),
    row(
        "R",
        "PASS",
        "R package/build metadata and validated external consumer are tracked under packaging/scientific-languages/r.",
        PASS_FUNCTIONAL_LANGUAGES_EVIDENCE,
        "Scientific-language checks confirm build/install/runtime/consumer and removal behavior.",
    ),
    row(
        "Ruby",
        "PASS",
        "Ruby library and executable gem under packaging/ruby.",
        PASS_RUBY_EVIDENCE,
        "Shipped as a RubyGem and validated with both RubyGems and Bundler.",
    ),
    row(
        "Dart",
        "PASS",
        "A Dart 3 pub project and typed launcher compile to a native server executable that consumes the packed SSHFling npm library through an explicit trusted Node bridge.",
        PASS_DART_EVIDENCE,
        "Dart SDK 3.12.2 completes formatting, analysis, offline dependency resolution, native compilation, and the packaged SSHFling runtime workflow.",
    ),
    row(
        "Lua",
        "PASS",
        "Lua 5.1/5.4 source module and CLI plus a LuaRocks package under packaging/lua.",
        PASS_SCRIPTING_LANGUAGE_EVIDENCE,
        "Both Lua ABIs execute the source API; LuaRocks 5.1 additionally validates install, library import, CLI, init, package, and removal.",
    ),
    row(
        "Perl",
        "PASS",
        "Perl module and executable with ExtUtils::MakeMaker metadata under packaging/perl.",
        PASS_PERL_EVIDENCE,
        "Shipped as a CPAN-style source distribution with isolated module and CLI validation.",
    ),
    row(
        "Scala",
        "PASS",
        "Scala 3.3 Maven and Gradle consumers compile against the published SSHFling Java library.",
        PASS_JVM_CONSUMER_EVIDENCE,
        "The clean Scala application invokes SSHFling.run and validates the bundled runtime workflow.",
    ),
    row(
        "Visual Basic/.NET",
        "PASS",
        "Visual Basic consumer project references the SSHFling NuGet library and invokes SSHFlingRunner.",
        PASS_DOTNET_EVIDENCE,
        "The language consumes the shipped .NET library through a clean local NuGet restore and runtime workflow.",
    ),
    domain_blocked("MATLAB", "A ProcessBuilder-based MATLAB launcher candidate is tracked under packaging/domain-languages/matlab.", "A licensed MATLAB runtime and configured JVM are required for conformance and packaging evidence."),
    row("Objective-C", "PASS", "Objective-C package metadata and runtime sources are tracked under packaging/systems-languages/objective-c.", PASS_SYSTEM_LANGUAGES_EVIDENCE, "The Objective-C shared library, external consumer, CLI runtime, and exit workflows compile and execute in an isolated build tree."),
    row(
        "Groovy",
        "PASS",
        "Groovy 5 Maven and Gradle consumers compile against the published SSHFling Java library.",
        PASS_JVM_CONSUMER_EVIDENCE,
        "The clean Groovy application invokes SSHFling.run and validates the bundled runtime workflow.",
    ),
    domain_blocked("Delphi/Object Pascal", "A Free Pascal/Object Pascal launcher candidate is tracked under packaging/domain-languages/object-pascal.", "Free Pascal validation does not establish Delphi compiler compatibility; both toolchain matrices remain external."),
    row(
        "Julia",
        "PASS",
        "Julia Pkg metadata, command source, runtime assets, and an external consumer are tracked under packaging/scientific-languages/julia.",
        PASS_FUNCTIONAL_LANGUAGES_EVIDENCE,
        "Julia package installation, import, command execution, external consumption, and removal are validated.",
    ),
    domain_not_applicable("HCL/Terraform", "HCL is configuration data and local-exec would be an unsafe shell-string side effect, not a typed launcher.", "infrastructure DSL"),
    row("Assembly", "PASS", "Assembly package metadata and runtime surface are tracked under packaging/systems-languages/assembly.", PASS_SYSTEM_LANGUAGES_EVIDENCE, "The assembly shared library, C ABI consumer, CLI runtime, debug artifact, and exit contract are validated in an isolated build tree."),
    row("COBOL", "PASS", "COBOL package metadata and runtime surface are tracked under packaging/systems-languages/cobol.", PASS_SYSTEM_LANGUAGES_EVIDENCE, "The COBOL module, CLI runtime, and exit contract compile and execute in an isolated build tree."),
    row("Fortran", "PASS", "Fortran package metadata and runtime surface are tracked under packaging/systems-languages/fortran.", PASS_SYSTEM_LANGUAGES_EVIDENCE, "The Fortran module, CLI runtime, and exit contract compile and execute in an isolated build tree."),
    domain_blocked("SAS", "The audit specifies the SAS XCMD execution boundary but intentionally supplies no unsafe macro.", "A licensed, policy-approved XCMD-enabled SAS runtime is unavailable and string-based execution is not portable."),
    domain_blocked("ABAP", "The audit specifies SAP external-command prerequisites but intentionally supplies no unvalidated transport.", "A licensed SAP system, SM69 definition, authorization design, namespace, and transport validation are required."),
    domain_not_applicable("Apex", "Apex cannot start host processes; an HTTP relayer would be a separate privileged service and protocol."),
    domain_blocked("PL/SQL", "The audit specifies Oracle external-job requirements but intentionally supplies no privileged database package.", "A licensed Oracle deployment, scheduler privileges, host credentials, and security review are required."),
    domain_not_applicable("T-SQL", "The only direct route is the disabled-by-default xp_cmdshell service-account escape hatch, which is rejected for new code."),
    row(
        "Elixir",
        "PASS",
        "Elixir package build and consumer validation are tracked under packaging/beam-languages/elixir.",
        PASS_FUNCTIONAL_LANGUAGES_EVIDENCE,
        "Mix package/build and external consumer validation are confirmed.",
    ),
    row(
        "Erlang",
        "PASS",
        "Erlang package build and consumer validation are tracked under packaging/beam-languages/erlang.",
        PASS_FUNCTIONAL_LANGUAGES_EVIDENCE,
        "Erlang package/build and external consumer validation are confirmed.",
    ),
    row(
        "Haskell",
        "PASS",
        "Cabal package and Haskell consumer with runtime/template resources under packaging/functional-languages/haskell.",
        PASS_FUNCTIONAL_EVIDENCE,
        "Cabal sources and a validated Haskell consumer flow are tracked and verified by the native functional-language validator.",
    ),
    row(
        "Clojure",
        "PASS",
        "Clojure 1.12 Maven and Gradle consumers invoke the published SSHFling Java library.",
        PASS_CLOJURE_EVIDENCE,
        "Both clean projects package Clojure namespaces and invoke SSHFling.run through clojure.main.",
    ),
    row(
        "F#",
        "PASS",
        "F# consumer project references the SSHFling NuGet library and invokes SSHFlingRunner.",
        PASS_DOTNET_EVIDENCE,
        "The language consumes the shipped .NET library through a clean local NuGet restore and runtime workflow.",
    ),
    row("OCaml", "PASS", "Dune/opam metadata and consumer validation are tracked under packaging/functional-languages/ocaml.", PASS_FUNCTIONAL_LANGUAGES_EVIDENCE, "OCaml package build/install and external-consumer validation are confirmed."),
    row("Zig", "PASS", "Zig package/build metadata are tracked under packaging/systems-languages/zig.", PASS_SYSTEM_LANGUAGES_EVIDENCE, "The Zig module and CLI are built into an isolated prefix and their runtime and exit contract are validated."),
    row("Nim", "PASS", "Nim package/build metadata are tracked under packaging/systems-languages/nim.", PASS_SYSTEM_LANGUAGES_EVIDENCE, "Nimble metadata, the Nim module and CLI build, runtime, and exit contract are validated in isolated caches."),
    row("Crystal", "PASS", "Crystal package/build metadata are tracked under packaging/systems-languages/crystal.", PASS_SYSTEM_LANGUAGES_EVIDENCE, "Crystal shard metadata, library-backed CLI build, runtime, and exit contract are validated in an isolated build tree."),
    row("D", "PASS", "D package/build metadata are tracked under packaging/systems-languages/d.", PASS_SYSTEM_LANGUAGES_EVIDENCE, "The D module, static library, CLI build, runtime, and exit contract are validated in an isolated build tree."),
    row("V", "PASS", "V package/build metadata and an external consumer are tracked under packaging/systems-languages/v.", PASS_SYSTEM_LANGUAGES_EVIDENCE, "V package build, install, runtime, external-consumer, exit-contract, and removal checks are validated."),
    row("Ada", "PASS", "Ada package/build metadata are tracked under packaging/systems-languages/ada.", PASS_SYSTEM_LANGUAGES_EVIDENCE, "Ada package metadata, public unit and CLI build, runtime, and exit contract are validated in an isolated build tree."),
    row("Common Lisp", "PASS", "ASDF/Quicklisp package and source are tracked under packaging/functional-languages/common-lisp.", PASS_FUNCTIONAL_LANGUAGES_EVIDENCE, "Common Lisp package/build and external-consumer validation are confirmed."),
    row("Scheme/Racket", "PASS", "Scheme (Guile) package/build metadata are tracked under packaging/functional-languages/scheme.", PASS_FUNCTIONAL_LANGUAGES_EVIDENCE, "Guile package/build/install and external-consumer validation are confirmed."),
    row("Prolog", "PASS", "SWI-Prolog package/build metadata are tracked under packaging/functional-languages/prolog.", PASS_FUNCTIONAL_LANGUAGES_EVIDENCE, "Prolog package/build/install and external-consumer validation are confirmed."),
    row(
        "Smalltalk",
        "BLOCKED",
        "Smalltalk package/build metadata are tracked under packaging/functional-languages/smalltalk.",
        BLOCKED_TOOLCHAIN_EVIDENCE,
        "Smalltalk validation is gated until GST toolchain is available.",
    ),
    row("Tcl", "PASS", "Versioned Tcl package, importable namespace, CLI, runtime, and templates under packaging/tcl.", PASS_SCRIPTING_LANGUAGE_EVIDENCE, "An isolated package require, API invocation, CLI init, asset checks, and removal are validated."),
    row("AWK", "PASS", "mawk-compatible source API and packaged CLI under packaging/awk.", PASS_SCRIPTING_LANGUAGE_EVIDENCE, "The source functions invoke the canonical runtime and the isolated package validates init assets and removal.", "shell"),
    row("sed", "PASS", "Versioned sed command file and packaged CLI under packaging/sed.", PASS_SCRIPTING_LANGUAGE_EVIDENCE, "The command file validates and extracts the canonical CLI version while rejecting malformed input.", "shell"),
    row("Zsh", "PASS", "Sourceable Zsh module and packaged CLI under packaging/shell-languages/zsh.", PASS_SCRIPTING_LANGUAGE_EVIDENCE, "Zsh executes the module API, exact version contract, init workflow, asset checks, and removal.", "shell"),
    row("Fish", "PASS", "Sourceable Fish module and packaged CLI under packaging/shell-languages/fish.", PASS_SCRIPTING_LANGUAGE_EVIDENCE, "Fish executes the module API, exact version contract, init workflow, asset checks, and removal.", "shell"),
    row("Nix", "PASS", "Generated Nix package metadata exists and is covered by cross-OS validation scope.", "docs/build-targets.md; cross-os validation workflow scope; release package site verifier", "Nix is supported as packaging metadata, not as a product runtime API.", "package DSL"),
    row(
        "Guix Scheme",
        "PASS",
        "A Guile module, Guix package definition, archive, CLI, runtime, and templates are tracked under packaging/guix-scheme.",
        PASS_SCRIPTING_LANGUAGE_EVIDENCE,
        "The Guile module, packaged CLI, init workflow, removal checks, and Guix package-definition dry-run are validated.",
        "package DSL",
    ),
    domain_not_applicable("Solidity", "EVM contracts cannot access host filesystems, networks, or process tables; a relayer would be a different product."),
    domain_not_applicable("Vyper", "Vyper targets the same isolated EVM and cannot launch a host SSHFling process."),
    domain_not_applicable("Move", "Move modules execute inside a blockchain VM and cannot create host processes."),
    row(
        "WebAssembly/WASI",
        "PASS",
        "WebAssembly/WASI source, build metadata, exported launcher functions, and a Node host adapter are tracked under packaging/systems-languages/webassembly-wasi.",
        PASS_SYSTEM_LANGUAGES_EVIDENCE,
        "The WASI module compiles, exports its typed launcher surface, and completes runtime and exit-contract checks through the host adapter.",
    ),
    row("Elm", "PASS", "Elm worker and Node-port consumer of the SSHFling npm library.", PASS_WEB_CONSUMER_EVIDENCE, "elm make and a complete Node port round trip are validated."),
    row("PureScript", "PASS", "PureScript module and Node FFI consumer of the SSHFling npm library.", PASS_WEB_CONSUMER_EVIDENCE, "The PureScript compiler and runtime FFI contract are validated."),
    row("Reason/ReScript", "PASS", "ReScript bindings and CommonJS consumer of the SSHFling npm library.", PASS_WEB_CONSUMER_EVIDENCE, "ReScript compilation and typed Node bindings are validated."),
    row("Forth", "PASS", "Forth package/build metadata are tracked under packaging/systems-languages/forth.", PASS_SYSTEM_LANGUAGES_EVIDENCE, "The Forth words, native bridge, CLI workflow, runtime assets, and exit contract are validated in an isolated build tree."),
    row("APL", "BLOCKED", "APL package/build metadata are tracked under packaging/scientific-languages/apl.", BLOCKED_TOOLCHAIN_EVIDENCE, "APL validation is blocked until Dyalog runtime/toolchain is available."),
    row("J", "PASS", "J package/build metadata, command source, runtime assets, and an external consumer are tracked under packaging/scientific-languages/j.", PASS_FUNCTIONAL_LANGUAGES_EVIDENCE, "J package installation, module loading, command execution, external consumption, and removal are validated."),
    domain_blocked("LabVIEW G", "The audit documents the System Exec VI candidate boundary without fabricating binary G source.", "A licensed LabVIEW version/OS matrix and genuine VI package are required for validation."),
    domain_not_applicable("Scratch", "Scratch projects are sandboxed; a privileged extension host would be a separate service, not a project launcher."),
    row("Q/KDB+", "BLOCKED", "Q/KDB+ package/build metadata are tracked under packaging/scientific-languages/q.", BLOCKED_TOOLCHAIN_EVIDENCE, "Q validation is blocked until q runtime/toolchain is available."),
    row(
        "Hack",
        "BLOCKED",
        "Hack source, Composer metadata, and a validated Node bridge are tracked under packaging/node/consumers/hack.",
        BLOCKED_WEB_TOOLCHAIN_EVIDENCE,
        "Promotion requires HHVM execution; the batch validator fails closed while hhvm is unavailable.",
    ),
    row(
        "CFML",
        "PASS",
        "CFML source, CommandBox metadata, template-relative bridge, and a validated Node bridge are tracked under packaging/node/consumers/cfml.",
        PASS_CFML_EVIDENCE,
        "CommandBox executes the server-side CFML template, which delegates to a trusted Node bridge consuming the packed SSHFling npm library.",
    ),
    domain_blocked("Wolfram Language", "A RunProcess-based Paclet source candidate is tracked under packaging/domain-languages/wolfram-language.", "A licensed Wolfram kernel exposed through wolframscript is required for conformance evidence."),
    domain_not_applicable("Verilog", "A simulator system task is a nonsynthesizable testbench escape, not a deployable SSHFling library.", "hardware description language"),
    domain_not_applicable("VHDL", "VHDL foreign and simulator interfaces do not form a synthesizable host launcher.", "hardware description language"),
    domain_not_applicable("SystemVerilog", "DPI and system tasks are simulator mechanisms, not synthesizable SSHFling packages.", "hardware description language"),
    domain_not_applicable("CUDA", "CUDA device code cannot launch host processes; a host C++ wrapper would duplicate the C++ surface."),
    domain_not_applicable("OpenCL C", "OpenCL kernels cannot create host processes; a host wrapper would be an existing C/C++ surface."),
    domain_not_applicable("GLSL", "Shader stages have no host process API."),
    domain_not_applicable("HLSL", "Shader stages have no host process API."),
    domain_not_applicable("WGSL", "WebGPU shader stages have no host process API."),
    row("Chapel", "PASS", "Chapel package/build metadata, module source, CLI, and external consumer are tracked under packaging/systems-languages/chapel.", PASS_SYSTEM_LANGUAGES_EVIDENCE, "Chapel validates Mason metadata, module import, CLI/runtime behavior, external consumption, removal, and post-removal import failure."),
    row("Pony", "PASS", "Pony package/build metadata and an external consumer are tracked under packaging/systems-languages/pony.", PASS_SYSTEM_LANGUAGES_EVIDENCE, "Pony package build, runtime, external-consumer, exit-contract, and removal checks are validated."),
    row("Janet", "PASS", "Janet package/build metadata, command source, runtime assets, and an external consumer are tracked under packaging/functional-languages/janet.", PASS_FUNCTIONAL_LANGUAGES_EVIDENCE, "Janet package installation, module import, command execution, external consumption, and removal are validated."),
    row("Odin", "PASS", "Odin collection/build metadata and an external consumer are tracked under packaging/systems-languages/odin.", PASS_SYSTEM_LANGUAGES_EVIDENCE, "Odin package build, collection import, runtime, external-consumer, exit-contract, and removal checks are validated."),
    row("Ballerina", "PASS", "Ballerina package/build metadata, public module, BALA resources, and external consumer tests are tracked under packaging/functional-languages/ballerina.", PASS_FUNCTIONAL_LANGUAGES_EVIDENCE, "Ballerina validates bal test, BALA packaging, local-repository install, external package consumption, exact output capture, removal, and import absence."),
    row("Gleam", "PASS", "Gleam package/build metadata are tracked under packaging/beam-languages/gleam.", PASS_FUNCTIONAL_LANGUAGES_EVIDENCE, "Gleam package/build and external-consumer validation are confirmed."),
    row("Roc", "BLOCKED", "Roc package/build metadata are tracked under packaging/functional-languages/roc.", BLOCKED_TOOLCHAIN_EVIDENCE, "Roc validation is blocked until Roc runtime/toolchain is available."),
    row("Red", "PASS", "Red package/build metadata and Red/System sources are tracked under packaging/systems-languages/red.", PASS_SYSTEM_LANGUAGES_EVIDENCE, "Red validates the pinned Red/System compiler, 32-bit launcher ABI, CLI/runtime behavior, init workflow, invalid option, and missing-runtime exit behavior."),
    row("Ring", "PASS", "Ring source package, library, POSIX status wrapper, and external consumer are tracked under packaging/functional-languages/ring.", PASS_FUNCTIONAL_LANGUAGES_EVIDENCE, "Ring library execution, CLI wrapper status mapping, init workflow, invalid option, missing runtime, and removal checks are validated."),
    row("Harbour", "PASS", "Harbour package/build metadata, xBase source, C bridge, CLI target, and runtime assets are tracked under packaging/systems-languages/harbour.", PASS_SYSTEM_LANGUAGES_EVIDENCE, "Harbour validates hbmk2 build, CLI/runtime behavior, init workflow, invalid option, and missing-runtime exit behavior."),
    domain_blocked("Xojo", "The audit records Xojo as a proprietary-toolchain blocker without fabricating a project.", "A licensed Xojo compiler and supported target matrix are unavailable."),
    domain_blocked("AutoHotkey", "An AutoHotkey v2 launcher candidate is tracked under packaging/domain-languages/autohotkey.", "AutoHotkey v2 on Windows is required for argument and status conformance evidence.", "automation language"),
    domain_blocked("AutoIt", "An AutoIt launcher candidate is tracked under packaging/domain-languages/autoit.", "AutoIt on Windows and its external licensing/toolchain are required for conformance evidence.", "automation language"),
    domain_blocked("AppleScript", "An AppleScript launcher candidate is tracked under packaging/domain-languages/applescript.", "macOS osacompile and osascript execution are required; the surface is non-interactive.", "automation language"),
    domain_blocked("VBScript", "A cscript-based VBScript launcher candidate is tracked under packaging/domain-languages/vbscript.", "Windows cscript execution is required and VBScript is deprecated by Microsoft.", "automation language"),
    domain_not_applicable("Power Query M", "Power Query M evaluates data transformations and has no supported local process-launch API."),
    domain_not_applicable("Q#", "Q# describes quantum operations; any subprocess call belongs to its classical host language."),
    domain_not_applicable("Arduino/Wiring", "Microcontroller sketches cannot host the canonical Python/OpenSSH runtime required by this launcher."),
    domain_not_applicable("MicroPython", "MicroPython targets constrained runtimes without the canonical subprocess/OpenSSH package contract."),
    domain_not_applicable("CircuitPython", "CircuitPython targets constrained boards without host process or OpenSSH support."),
    row("Elvish", "PASS", "An Elvish module, archive, packaged CLI, runtime, and templates are tracked under packaging/shell-languages/elvish.", PASS_SCRIPTING_LANGUAGE_EVIDENCE, "Elvish 0.21 executes the module API, exact version contract, init workflow, asset checks, and removal.", "shell"),
    row("Nushell", "PASS", "A Nushell module, archive, packaged CLI, runtime, and templates are tracked under packaging/shell-languages/nushell.", PASS_SCRIPTING_LANGUAGE_EVIDENCE, "Nushell 0.113 executes the wrapped module API, exact version contract, init workflow, asset checks, and removal.", "shell"),
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
    row("HTML/CSS", "PASS", "Static HTML/CSS output generated after a trusted Node-side SSHFling package check.", PASS_WEB_CONSUMER_EVIDENCE, "The emitted page is script-free and explicitly does not perform browser-side SSH.", "markup/style"),
    row("Svelte", "PASS", "Svelte server component consuming the SSHFling npm library under Node.", PASS_WEB_CONSUMER_EVIDENCE, "Svelte server compilation and rendering are validated without browser process access.", "framework"),
    row("Vue", "PASS", "Vue server-rendered component consuming the SSHFling npm library under Node.", PASS_WEB_CONSUMER_EVIDENCE, "Vue SSR executes and validates the package in a trusted server process.", "framework"),
    row("React/JSX", "PASS", "React JSX server component consuming the SSHFling npm library under Node.", PASS_WEB_CONSUMER_EVIDENCE, "JSX compilation and React static rendering validate the Node-only integration.", "framework"),
    row("Angular", "PASS", "Strict TypeScript Angular server component consuming the SSHFling npm library.", PASS_WEB_CONSUMER_EVIDENCE, "Angular server rendering validates the integration without exposing process access to browsers.", "framework"),
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
