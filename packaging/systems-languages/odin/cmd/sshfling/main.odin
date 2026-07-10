package main

import "core:os"
import "sshfling:sshfling"

main :: proc() {
    arguments := make([]cstring, len(os.args) - 1)
    for argument, index in os.args[1:] {
        arguments[index] = cstring(raw_data(argument))
    }
    os.exit(sshfling.run(arguments))
}
