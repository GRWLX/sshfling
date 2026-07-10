#include <sshfling_assembly.h>

#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
    const char *arguments[] = {"--version"};

    if (argc != 2 || strcmp(sshfling_assembly_version(), argv[1]) != 0) {
        fprintf(stderr, "Assembly library version mismatch: %s\n", sshfling_assembly_version());
        return 1;
    }
    return sshfling_assembly_run(1, arguments);
}
