(* SPDX-License-Identifier: MIT *)
BeginPackage["SSHFling`"];

RunSSHFling::usage =
    "RunSSHFling[arguments] starts an installed SSHFling executable and " <>
    "returns the RunProcess result association.";
RunSSHFlingExitCode::usage =
    "RunSSHFlingExitCode[arguments] starts SSHFling and returns only its exit code.";
RunSSHFling::badargs = "Arguments must be a list of strings without NUL characters.";
RunSSHFling::badexe = "The executable must be Automatic or a nonempty string without NUL characters.";

Options[RunSSHFling] = {"Executable" -> Automatic};
Options[RunSSHFlingExitCode] = Options[RunSSHFling];

Begin["`Private`"];

resolveExecutable[Automatic] := Module[{configured},
    configured = Environment["SSHFLING_EXECUTABLE"];
    If[StringQ[configured] && StringLength[configured] > 0, configured, "sshfling"]
];
resolveExecutable[value_String] /; StringLength[value] > 0 && StringFreeQ[value, FromCharacterCode[0]] := value;
resolveExecutable[_] := (Message[RunSSHFling::badexe]; $Failed);

RunSSHFling[arguments_List, OptionsPattern[]] := Module[{executable},
    If[!AllTrue[arguments, StringQ[#] && StringFreeQ[#, FromCharacterCode[0]] &],
        Message[RunSSHFling::badargs];
        Return[$Failed]
    ];
    executable = resolveExecutable[OptionValue["Executable"]];
    If[executable === $Failed, Return[$Failed]];
    RunProcess[Prepend[arguments, executable]]
];
RunSSHFling[_, OptionsPattern[]] := (Message[RunSSHFling::badargs]; $Failed);

RunSSHFlingExitCode[arguments_List, OptionsPattern[]] := Module[{result},
    result = RunSSHFling[arguments, "Executable" -> OptionValue["Executable"]];
    If[AssociationQ[result], result["ExitCode"], $Failed]
];
RunSSHFlingExitCode[_, OptionsPattern[]] := (Message[RunSSHFling::badargs]; $Failed);

End[];
EndPackage[];
