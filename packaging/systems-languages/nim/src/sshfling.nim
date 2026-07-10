{.compile: "../common/sshfling_launcher.c".}

const sshflingVersion* = "0.0.0"

proc launcherVersion(): cstring
  {.cdecl, importc: "sshfling_launcher_version".}
proc launcherRun(count: csize_t, arguments: ptr cstring): cint
  {.cdecl, importc: "sshfling_launcher_run".}

proc runtimeVersion*(): string =
  result = $launcherVersion()

proc run*(arguments: openArray[string]): int =
  var pointers = newSeq[cstring](arguments.len)
  for index, argument in arguments:
    pointers[index] = argument.cstring

  let base = if pointers.len == 0: nil else: addr pointers[0]
  result = int(launcherRun(csize_t(pointers.len), base))
