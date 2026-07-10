module consumer;

import sshfling : run, runtimeVersion, sshflingVersion;

int main(string[] arguments) {
    if (arguments.length != 2 || sshflingVersion != arguments[1] || runtimeVersion() != arguments[1]) {
        return 1;
    }
    return run(["--version"]);
}
