(* SPDX-License-Identifier: MIT *)
packageRoot = DirectoryName[DirectoryName[$InputFileName]];
Get[FileNameJoin[{packageRoot, "src", "SSHFling.wl"}]];
status = SSHFling`RunSSHFling[Rest[$ScriptCommandLine]];
Exit[If[IntegerQ[status], status, 1]];
