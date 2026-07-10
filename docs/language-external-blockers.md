# Domain-language external blockers

Audit date: 2026-07-10.

All languages in this document remain non-PASS. The generated support matrix
classifies unavailable proprietary/platform runtimes as `BLOCKED` and semantic
non-process domains as `NOT_APPLICABLE`. The files under
`packaging/domain-languages/` are quarantined audit evidence, not release
packages, and `packaging/build-domain-languages.sh package LANGUAGE` fails for
every row.

## Acceptance boundary

An SSHFling launcher must start a real installed `sshfling` process, preserve
argument boundaries, wait for completion, and expose the child status. A file
that only parses, emits an event, submits a cloud job, calls an unrelated API,
or demonstrates language syntax is not a launcher. A platform escape hatch
that runs as a database/service account is not accepted merely because it can
execute a shell command.

The audit host has Bash and ShellCheck, but none of the candidate-language
runtimes (`matlab`, `wolframscript`, AutoHotkey, AutoIt, `osascript`,
`cscript.exe`, or `fpc`). Candidate gates therefore fail closed when their
external validator is absent. The audit action itself checks the complete
33-row inventory, tracked candidate source, blocker entry for every row,
quarantine wording, and shell syntax/lint without producing an artifact.

## Real launcher candidates, not support claims

<!-- target:matlab -->
### MATLAB

`matlab/+sshfling/run.m` is a real non-shell launcher. It constructs a Java
`ProcessBuilder` argument list, inherits standard streams, waits, and returns
the status. The gate uses `matlab -batch` and a fake executable whose path and
arguments contain spaces and shell metacharacters. MATLAB and a configured JVM
are external requirements; MATLAB is not installed here and its use is subject
to MathWorks licensing. MathWorks documents both [calling Java from MATLAB](https://www.mathworks.com/help/matlab/using-java-libraries-in-matlab.html)
and the separate [JRE configuration requirement](https://www.mathworks.com/help/matlab/matlab_external/configure-your-system-to-use-java.html).
No `.mltbx` is emitted.

<!-- target:wolfram-language -->
### Wolfram Language

The candidate Paclet source calls `RunProcess` with a command list, so arguments
are not shell-concatenated, and returns the process result association and exit
code. `RunProcess` captures stdin/stdout/stderr; this candidate is not suitable
for an interactive password prompt. The gate requires a licensed Wolfram
kernel exposed by `wolframscript`, which is absent here. The command-list and
result behavior is defined by the official [RunProcess documentation](https://reference.wolfram.com/language/ref/RunProcess.html?view=all).
No Paclet archive is emitted.

<!-- target:autohotkey -->
### AutoHotkey

The AutoHotkey v2 class builds a Windows command line using the standard
backslash-before-quote algorithm, invokes `RunWait`, and returns the child exit
code. The focused self-test requires AutoHotkey v2 on Windows and verifies
status propagation through `cmd.exe`. AutoHotkey is absent on this Linux host;
no compiled script is emitted and no runtime is redistributed.

<!-- target:autoit -->
### AutoIt

The AutoIt UDF quotes each Windows argument, invokes `RunWait`, and maps a
launch failure to 127. AutoIt's documentation confirms that
[`RunWait` returns the child exit code](https://www.autoitscript.com/autoit3/docs/functions/RunWait.htm).
The compiler/runtime and its license are external Windows prerequisites; they
are absent here. No `.a3x` or executable is emitted.

<!-- target:applescript -->
### AppleScript

The candidate uses `do shell script` with `quoted form of` for the executable
and every argument, waits, captures output, and reports the shell status.
Apple documents that `quoted form` is safe from further shell interpretation
and that nonzero command status becomes the AppleScript error number in its
[command-line tools guide](https://developer.apple.com/library/archive/documentation/LanguagesUtilities/Conceptual/MacAutomationScriptingGuide/CallCommandLineUtilities.html)
and [language reference](https://developer.apple.com/library/archive/documentation/AppleScript/Conceptual/AppleScriptLangGuide/reference/ASLR_cmds.html).
Because `do shell script` captures streams, this surface is non-interactive and
cannot service a password prompt. Compilation and the focused probe require
macOS `osacompile`/`osascript`; neither exists on this Linux host. No `.scpt` is
emitted.

<!-- target:vbscript -->
### VBScript

The candidate uses `WScript.Shell.Run` with Windows argument quoting, waits,
and returns the process status. It is non-interactive and requires `cscript.exe`
on Windows. Microsoft lists VBScript as deprecated and says it will become a
Feature on Demand before removal in a future Windows release in the official
[Windows deprecated-features inventory](https://learn.microsoft.com/windows/whats-new/deprecated-features).
That lifecycle prevents a durable release claim even if the focused gate passes
on a current Windows worker. No Windows artifact is emitted.

<!-- target:delphi-object-pascal -->
### Delphi/Object Pascal

The Object Pascal unit uses Free Pascal's `TProcess`, passes parameters through
the process API, inherits the host console, waits, and returns `ExitStatus`. The
gate requires `fpc`, compiles only into a temporary directory, and probes a fake
SSHFling executable. `fpc` is absent here. Passing this gate would establish a
Free Pascal surface only; it would not establish Delphi compatibility. A Delphi
claim additionally requires an Embarcadero-supported compiler/platform matrix
and license, neither of which is available in this repository. No archive is
emitted.

## Database and infrastructure DSL blockers

<!-- target:sql -->
### SQL

Standard SQL has no portable child-process or OpenSSH API. Database-specific
extensions would turn this into one of the privileged dialect cases below,
not a generic SQL package. There is also no SSHFling schema, migration, or
database protocol to expose. A `.sql` file would therefore be unrelated syntax.

<!-- target:plsql -->
### PL/SQL

Oracle external jobs require an Oracle Database deployment, scheduler/external
job privileges, host credentials/agent configuration, and a licensed Oracle
validation environment. Running SSHFling from the database service boundary
would create a privileged host-command channel and does not provide a safe,
portable argument-vector API. No Oracle instance or SQL*Plus/SQLcl validator is
available, so no PL/SQL package is supplied.

<!-- target:tsql -->
### T-SQL

The apparent execution route is `xp_cmdshell`, which starts a process with the
SQL Server service account (or a configured proxy), accepts a command string,
and is disabled by default. Microsoft explicitly says newly developed code
should not use it and it should generally remain disabled in the official
[`xp_cmdshell` configuration guidance](https://learn.microsoft.com/sql/database-engine/configure-windows/xp-cmdshell-server-configuration-option).
Enabling it for SSHFling would enlarge the database attack surface, so the gate
is semantic/security-blocked even if SQL Server and `sqlcmd` become available.

<!-- target:hcl-terraform -->
### HCL/Terraform

HCL is configuration data, not a process library API. Terraform `local-exec`
would be a shell-string provisioner tied to resource lifecycle and state, not a
typed SSHFling launcher; temporary access credentials and side effects are a
poor fit for plan/apply semantics. Neither Terraform nor OpenTofu is installed.
A future Terraform provider would need a separately designed protocol, state
redaction model, provider signing/distribution process, acceptance tests, and a
license review of the selected Terraform/OpenTofu toolchain.

## Smart-contract and quantum blockers

<!-- target:solidity -->
### Solidity

The EVM cannot access a host filesystem, network, or process table. Solidity's
documentation describes the EVM as isolated from other processes in its
[smart-contract introduction](https://docs.soliditylang.org/en/latest/introduction-to-smart-contracts.html).
A contract event plus an off-chain relayer would be a new privileged protocol,
not a Solidity SSHFling launcher, and no such authenticated relayer exists.
`solc` and Foundry are absent, but installing them would not remove the semantic
blocker. No contract is supplied.

<!-- target:vyper -->
### Vyper

Vyper targets the same EVM isolation boundary as Solidity. It cannot start
OpenSSH or `sshfling`; an oracle/relayer design would require a new off-chain
service, authorization model, replay protection, expiry semantics, and audit.
The Vyper compiler is absent, but tooling is not the controlling blocker.

<!-- target:move -->
### Move

Move modules execute inside a blockchain VM and cannot create host processes.
Chain-specific event emission would only signal an unimplemented off-chain
agent and would not be a launcher. A real integration would first need a chosen
Move chain/runtime, authenticated relayer protocol, finality/reorg policy,
expiry rules, and audits. No Move toolchain is installed.

<!-- target:qsharp -->
### Q#

Q# describes quantum operations; host integration is supplied by Python or
another classical host. Microsoft's current Q# guidance explicitly presents
Python as the host that calls Q# operations in [Q# development options](https://learn.microsoft.com/azure/quantum/qsharp-ways-to-work).
Putting `subprocess` in that Python host would merely reuse SSHFling's existing
Python surface, not create a Q# launcher. The QDK is absent and no Q# source is
supplied.

## HDL, accelerator, and shader blockers

<!-- target:verilog -->
### Verilog

Verilog describes/simulates hardware. A testbench `$system` task is a simulator
escape hatch, not synthesizable hardware or a deployable SSHFling library. No
simulator, FPGA target, board flow, or SSH hardware core is defined.

<!-- target:vhdl -->
### VHDL

VHDL describes/simulates hardware. Foreign interfaces or simulator file I/O do
not become a host launcher and are generally nonsynthesizable. No GHDL/vendor
simulator, FPGA target, board flow, or SSH hardware core is defined.

<!-- target:systemverilog -->
### SystemVerilog

SystemVerilog DPI or `$system` can escape from a simulator into C/shell code,
but that would be a testbench mechanism and existing C launcher reuse, not a
synthesizable SystemVerilog package. No simulator or FPGA flow is installed.

<!-- target:cuda -->
### CUDA

CUDA device code cannot launch a host process. A `.cu` translation unit whose
host C++ section starts SSHFling would only duplicate the existing C/C++
launcher while adding an irrelevant GPU dependency. `nvcc`, CUDA libraries,
an NVIDIA driver/GPU validation target, and acceptance of the [CUDA Toolkit
license](https://docs.nvidia.com/cuda/eula/contents.html) are all absent.

<!-- target:opencl-c -->
### OpenCL C

OpenCL C kernels execute on a compute device and cannot create host processes.
An OpenCL host wrapper would be C/C++ plus an irrelevant ICD/device dependency,
not an OpenCL C launcher. No OpenCL compiler, ICD, or device matrix is present.

<!-- target:glsl -->
### GLSL

GLSL shader stages have no host process API. A graphics host program that
spawns SSHFling would be a launcher in its host language and the shader would
be decorative. No shader source is supplied; `glslangValidator` and a graphics
runtime are absent.

<!-- target:hlsl -->
### HLSL

HLSL shader stages have no host process API. A DirectX host wrapper would be
C++/.NET and would not establish an HLSL SSHFling surface. DXC and a DirectX
runtime/device validation matrix are absent.

<!-- target:wgsl -->
### WGSL

WGSL runs in WebGPU shader stages without process access. JavaScript/Rust host
code could spawn a process only outside the shader and would reuse an existing
language surface. No WebGPU implementation or WGSL validator is installed.

## Proprietary application/platform blockers

<!-- target:sas -->
### SAS

SAS host execution depends on the administrator-controlled XCMD facility and
string command construction. A macro would run with the SAS server/session
identity, cannot provide a portable argument-vector contract, and may be
disabled by policy. A licensed SAS runtime and an approved XCMD-enabled test
environment are absent. Enabling XCMD solely for this package is not accepted.

<!-- target:abap -->
### ABAP

ABAP can execute only a Basis-registered external command through the SAP
external-command interface. SAP documents that `SXPG_COMMAND_EXECUTE` requires
an SM69 command definition, `S_LOG_COM` authorization, target-system policy,
parameter filtering, and reports output through a protocol table in the
official [ABAP platform reference](https://help.sap.com/docs/ABAP_PLATFORM_NEW/7bfe8cdcfbb040dcb6702dada8c3e2f0/4d95eb2759ca6c14e10000000a15822b.html).
This repository has no SAP system, transport namespace, SM69 definition,
authorization design, or SAP license. A standalone `.abap` class could not be
validated or safely deployed, so none is supplied.

<!-- target:apex -->
### Apex

Apex runs in Salesforce's managed runtime and cannot start a host process.
Its external escape is an authenticated HTTP callout using a Named Credential,
as Salesforce documents in [Call APIs from Apex](https://developer.salesforce.com/docs/platform/lwc/guide/data-api-calls-apex.html).
SSHFling has no approved remote launcher service or Apex authentication/replay
protocol. A callout to a nonexistent service would be a syntax sample. No
Salesforce org, namespace, scratch-org definition, or CLI validation is present.

<!-- target:labview-g -->
### LabVIEW G

LabVIEW can call a command through System Exec VI, but G source is a graphical
VI/project artifact requiring NI tooling; a screenshot or textual pseudo-VI is
not source. There is no licensed LabVIEW environment, supported version/OS
matrix, VI package, or headless validation path here. No binary VI is fabricated.

<!-- target:scratch -->
### Scratch

Scratch projects execute in a sandbox and have no local process API. A custom
extension capable of host execution would require a separately installed,
privileged JavaScript extension host and security model; the `.sb3` project
would not itself launch SSHFling. No extension service or Scratch package is
defined.

<!-- target:power-query-m -->
### Power Query M

Power Query M is an expression/data-shaping language without a child-process
API. A custom connector can call approved data sources but is not a local
process launcher and would require connector signing, privacy-level behavior,
gateway/credential design, and Excel/Power BI validation. Those proprietary
hosts and SDKs are absent.

<!-- target:xojo -->
### Xojo

Xojo's host `Shell` class could run a command, but a compilable/packageable
surface requires a real Xojo project, supported desktop targets, and the
proprietary IDE/compiler. There is no licensed Xojo installation or stable
headless validation path here. A lone `.xojo_code` snippet would not establish
a package, so no source is supplied.

## Embedded-platform blockers

<!-- target:arduino-wiring -->
### Arduino/Wiring

Arduino sketches run on microcontrollers without a host process table or an
installed OpenSSH/SSHFling executable. Implementing SSH over a network stack
would be a new embedded SSH client, not a launcher around SSHFling's CLI. No
board, core, network library, memory budget, or `arduino-cli` toolchain is
selected.

<!-- target:micropython -->
### MicroPython

Typical MicroPython ports do not have a host `sshfling` executable to spawn;
port-specific `os.system` behavior on a Unix test port would not establish
embedded support. A real network integration would require a supported board,
TLS/SSH implementation, secure key storage, and firmware tests. No MicroPython
runtime or device is present.

<!-- target:circuitpython -->
### CircuitPython

CircuitPython targets constrained boards and intentionally exposes hardware
and Python APIs rather than arbitrary host process creation. There is no local
SSHFling process to launch. Support would require a separately designed network
protocol/client, board compatibility matrix, secure credential storage, and
device tests. No CircuitPython runtime or board is present.

## Gate interpretation

- `audit` succeeding means the inventory and fail-closed policy are internally
  consistent.
- `status` is informational and reports missing local validators without
  changing support.
- `gate TARGET` returns 127 when an external validator is unavailable, 78 for a
  semantic/platform blocker, or nonzero when a focused conformance probe fails.
- `package TARGET` always returns 78. There is intentionally no artifact,
  release registration, generated-matrix update, or support promotion.
