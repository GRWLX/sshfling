module app;

import sshfling : run;

int main(string[] arguments) {
    return run(arguments[1 .. $]);
}
