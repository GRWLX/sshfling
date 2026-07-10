package sshfling

import "core:c"

foreign import launcher "system:sshfling_launcher"

foreign launcher {
    @(link_name="sshfling_launcher_version")
    launcher_version :: proc() -> cstring ---
    @(link_name="sshfling_launcher_run")
    launcher_run :: proc(count: uintptr, arguments: [^]cstring) -> c.int ---
}

VERSION :: "0.0.0"

runtime_version :: proc() -> string {
    return string(launcher_version())
}

run :: proc(arguments: []cstring) -> int {
    base: [^]cstring = nil
    if len(arguments) > 0 {
        base = raw_data(arguments)
    }
    return int(launcher_run(uintptr(len(arguments)), base))
}
