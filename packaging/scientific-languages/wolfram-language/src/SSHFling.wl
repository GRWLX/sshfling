(* SPDX-License-Identifier: MIT *)
BeginPackage["SSHFling`"];

PackageVersion::usage = "PackageVersion[] returns the SSHFling package version.";
RuntimePath::usage = "RuntimePath[] returns the bundled SSHFling runtime path.";
TemplateDirectory::usage = "TemplateDirectory[] returns the bundled template directory.";
RunSSHFling::usage =
    "RunSSHFling[arguments] starts the bundled SSHFling runtime and returns its exit status.";
RunSSHFlingExitCode::usage =
    "RunSSHFlingExitCode[arguments] is an alias for RunSSHFling[arguments].";
RunSSHFling::badargs = "Arguments must be a list of strings without NUL characters.";
RunSSHFling::badwrapper = "The Mathics runner wrapper is not available.";

Begin["`Private`"];

packageVersion = "0.0.0";
packageRootValue = DirectoryName[DirectoryName[$InputFileName]];

configured[name_, fallback_] := Module[{value},
    value = Environment[name];
    If[StringQ[value] && StringLength[value] > 0, value, fallback]
];

packageRoot[] := configured["SSHFLING_PACKAGE_ROOT", packageRootValue];

PackageVersion[] := packageVersion;

RuntimePath[] := configured[
    "SSHFLING_RUNTIME",
    FileNameJoin[{packageRoot[], "runtime", "sshfling.py"}]
];

TemplateDirectory[] := configured[
    "SSHFLING_TEMPLATE_DIR",
    FileNameJoin[{packageRoot[], "runtime", "templates"}]
];

pythonExecutable[] := configured["SSHFLING_PYTHON", "python3"];

wrapperPath[] := configured[
    "SSHFLING_MATHICS_WRAPPER",
    FileNameJoin[{packageRoot[], "bin", "sshfling-mathics-runner"}]
];

validArgumentQ[value_] := StringQ[value] && FreeQ[ToCharacterCode[value], 0];

hexDigit[index_] := Characters["0123456789abcdef"][[index + 1]];

byteHex[value_] := StringJoin[
    hexDigit[Quotient[value, 16]],
    hexDigit[Mod[value, 16]]
];

hexEncode[value_String] := StringJoin[byteHex /@ ToCharacterCode[value, "UTF8"]];

argumentPayload[arguments_] := Module[{encoded},
    encoded = hexEncode /@ arguments;
    If[Length[encoded] == 0, "", StringJoin[Riffle[encoded, "\n"]] <> "\n"]
];

writeArgumentFile[arguments_] := Module[{path, stream},
    path = CreateTemporary[];
    stream = OpenWrite[path];
    WriteString[stream, argumentPayload[arguments]];
    Close[stream];
    path
];

RunSSHFling[arguments_List] := Module[{wrapper, argumentFile, status},
    If[!AllTrue[arguments, validArgumentQ],
        Message[RunSSHFling::badargs];
        Return[$Failed]
    ];
    wrapper = wrapperPath[];
    If[!FileExistsQ[wrapper],
        Message[RunSSHFling::badwrapper];
        Return[127]
    ];
    argumentFile = writeArgumentFile[arguments];
    SetEnvironment[{
        "SSHFLING_MATHICS_ARG_FILE" -> argumentFile,
        "SSHFLING_PACKAGE_ROOT" -> packageRoot[],
        "SSHFLING_RUNTIME" -> RuntimePath[],
        "SSHFLING_TEMPLATE_DIR" -> TemplateDirectory[],
        "SSHFLING_PYTHON" -> pythonExecutable[]
    }];
    status = Run[wrapper];
    If[FileExistsQ[argumentFile], DeleteFile[argumentFile]];
    status
];
RunSSHFling[_] := (Message[RunSSHFling::badargs]; $Failed);

RunSSHFlingExitCode[arguments_List] := RunSSHFling[arguments];
RunSSHFlingExitCode[_] := (Message[RunSSHFling::badargs]; $Failed);

End[];
EndPackage[];
