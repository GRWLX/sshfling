module main

import os
import sshfling

fn main() {
	if os.args.len != 2 || sshfling.version != os.args[1]
		|| sshfling.runtime_version() != os.args[1] {
		exit(1)
	}
	exit(sshfling.run(['--version']))
}
