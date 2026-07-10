module main

import os
import sshfling

fn main() {
    exit(sshfling.run(os.args[1..]))
}
