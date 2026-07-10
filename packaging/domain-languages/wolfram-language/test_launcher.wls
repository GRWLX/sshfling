(* SPDX-License-Identifier: MIT *)
packageRoot = DirectoryName[$InputFileName];
Get[FileNameJoin[{packageRoot, "Kernel", "SSHFling.wl"}]];
executable = Environment["SSHFLING_TEST_EXECUTABLE"];
If[!StringQ[executable] || StringLength[executable] == 0, Exit[96]];
result = SSHFling`RunSSHFling[
    {"--probe", "argument with spaces", "literal;$()&"},
    "Executable" -> executable
];
If[
    AssociationQ[result] &&
        result["ExitCode"] === 23 &&
        StringContainsQ[result["StandardOutput"], "fake sshfling stdout"] &&
        StringContainsQ[result["StandardError"], "fake sshfling stderr"],
    Exit[0],
    Exit[1]
];
