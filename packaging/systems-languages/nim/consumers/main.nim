import std/os
import sshfling

if paramCount() != 1 or sshflingVersion != paramStr(1) or runtimeVersion() != paramStr(1):
  quit(1)
quit(run(["--version"]))
