#include <sshfling/sshfling.h>

#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc != 2 || strcmp(sshfling_version(), argv[1]) != 0) {
        fprintf(stderr, "C library version mismatch: %s\n", sshfling_version());
        return 1;
    }
    const char *arguments[] = {"--version"};
    return sshfling_run(1, arguments);
}
