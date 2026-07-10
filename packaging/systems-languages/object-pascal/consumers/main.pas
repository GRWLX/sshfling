{ SPDX-License-Identifier: MIT }
program SSHFlingObjectPascalConsumer;

{$mode objfpc}{$H+}

uses
  SSHFling;

var
  Arguments: TStringArray;
begin
  SetLength(Arguments, 1);
  Arguments[0] := '--version';
  Halt(RunSSHFling(Arguments));
end.

