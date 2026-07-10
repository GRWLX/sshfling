module sshfling

#flag -I @VMODROOT/common
#flag @VMODROOT/common/sshfling_launcher.c
#include "sshfling_launcher.h"

fn C.sshfling_launcher_version() &char
fn C.sshfling_launcher_run(count usize, arguments &&char) int

pub const version = '0.0.0'

pub fn runtime_version() string {
    return unsafe { cstring_to_vstring(C.sshfling_launcher_version()) }
}

pub fn run(arguments []string) int {
    mut pointers := []&char{cap: arguments.len}
    for argument in arguments {
        pointers << argument.str
    }
    if pointers.len == 0 {
        return C.sshfling_launcher_run(0, unsafe { nil })
    }
    return C.sshfling_launcher_run(pointers.len, &&char(pointers.data))
}
