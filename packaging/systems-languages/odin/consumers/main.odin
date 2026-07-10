package main

import "core:os"
import "sshfling:sshfling"

main :: proc() {
    if len(os.args) != 2 || sshfling.VERSION != os.args[1] ||
       sshfling.runtime_version() != os.args[1] {
        os.exit(1)
    }
    arguments := []cstring{cstring("--version")}
    os.exit(sshfling.run(arguments))
}
