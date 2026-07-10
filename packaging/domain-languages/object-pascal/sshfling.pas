{ SPDX-License-Identifier: MIT }
unit SSHFling;

{$mode objfpc}{$H+}

interface

type
  TStringArray = array of string;

{ Starts an installed SSHFling executable, waits, and returns its exit status. }
function RunSSHFling(const Arguments: TStringArray;
  const ExecutableOverride: string = ''): LongInt;

implementation

uses
  Process, SysUtils;

function RunSSHFling(const Arguments: TStringArray;
  const ExecutableOverride: string): LongInt;
var
  ArgumentValue: string;
  ExecutableName: string;
  Launcher: TProcess;
begin
  ExecutableName := ExecutableOverride;
  if ExecutableName = '' then
    ExecutableName := GetEnvironmentVariable('SSHFLING_EXECUTABLE');
  if ExecutableName = '' then
    ExecutableName := 'sshfling';

  if Pos(#0, ExecutableName) <> 0 then
    raise EArgumentException.Create('SSHFling executable contains a NUL character');

  Launcher := TProcess.Create(nil);
  try
    Launcher.Executable := ExecutableName;
    Launcher.Options := [poWaitOnExit];
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
