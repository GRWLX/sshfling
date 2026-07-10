{ SPDX-License-Identifier: MIT }
unit SSHFling;

{$mode objfpc}{$H+}

interface

type
  TStringArray = array of string;

function RunSSHFling(const Arguments: TStringArray;
  const ExecutableOverride: string = ''): LongInt;

implementation

uses
  Process, SysUtils;

function ConfiguredPython: string;
begin
  Result := GetEnvironmentVariable('SSHFLING_PYTHON');
  if Result = '' then
    Result := 'python3';
end;

function RuntimeScript: string;
var
  RuntimeDirectory: string;
begin
  RuntimeDirectory := GetEnvironmentVariable('SSHFLING_RUNTIME_DIR');
  if RuntimeDirectory = '' then
    RuntimeDirectory := IncludeTrailingPathDelimiter(ExtractFileDir(ParamStr(0))) + 'runtime';
  Result := IncludeTrailingPathDelimiter(RuntimeDirectory) + 'sshfling.py';
end;

function RunSSHFling(const Arguments: TStringArray;
  const ExecutableOverride: string): LongInt;
var
  ArgumentValue: string;
  ExecutableName: string;
  Launcher: TProcess;
  Script: string;
begin
  ExecutableName := ExecutableOverride;
  if ExecutableName = '' then
    ExecutableName := GetEnvironmentVariable('SSHFLING_EXECUTABLE');

  Launcher := TProcess.Create(nil);
  try
    Launcher.Options := [poWaitOnExit];
    if ExecutableName <> '' then
    begin
      if Pos(#0, ExecutableName) <> 0 then
        raise EArgumentException.Create('SSHFling executable contains a NUL character');
      Launcher.Executable := ExecutableName;
    end
    else
    begin
      Script := RuntimeScript;
      if not FileExists(Script) then
      begin
        WriteLn(StdErr, 'sshfling: runtime is missing: ', Script);
        Exit(127);
      end;
      Launcher.Executable := ConfiguredPython;
      Launcher.Parameters.Add(Script);
    end;

    for ArgumentValue in Arguments do
    begin
      if Pos(#0, ArgumentValue) <> 0 then
        raise EArgumentException.Create('SSHFling argument contains a NUL character');
      Launcher.Parameters.Add(ArgumentValue);
    end;

    try
      Launcher.Execute;
      Result := Launcher.ExitStatus;
    except
      on E: EProcess do
      begin
        WriteLn(StdErr, 'Could not start SSHFling: ', E.Message);
        Result := 127;
      end;
    end;
  finally
    Launcher.Free;
  end;
end;

end.

