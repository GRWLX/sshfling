{ SPDX-License-Identifier: MIT }
program SSHFlingCLI;

{$mode objfpc}{$H+}

uses
  SSHFling;

var
  Arguments: TStringArray;
  Index: LongInt;
begin
  SetLength(Arguments, ParamCount);
  for Index := 1 to ParamCount do
    Arguments[Index - 1] := ParamStr(Index);
  Halt(RunSSHFling(Arguments));
end.
