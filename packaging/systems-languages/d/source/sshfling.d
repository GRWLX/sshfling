module sshfling;

import std.string : fromStringz, toStringz;

enum sshflingVersion = "0.0.0";

extern(C) {
    const(char)* sshfling_launcher_version();
    int sshfling_launcher_run(size_t count, const(char*)* arguments);
}

string runtimeVersion() {
    return sshfling_launcher_version().fromStringz.idup;
}

int run(const string[] arguments) {
    const(char)*[] pointers;
    pointers.reserve(arguments.length);
    foreach (argument; arguments) {
        pointers ~= argument.toStringz;
    }
    return sshfling_launcher_run(
        arguments.length,
        pointers.length == 0 ? null : pointers.ptr
    );
}
