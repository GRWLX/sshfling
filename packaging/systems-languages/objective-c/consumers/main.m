#import <SSHFling/SSHFling.h>

#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
    const char *arguments[] = {"--version"};

    if (argc != 2 || strcmp([SSHFling version], argv[1]) != 0) {
        fprintf(stderr, "Objective-C library version mismatch: %s\n", [SSHFling version]);
        return 1;
    }
    return [SSHFling runWithArgumentCount:1 arguments:arguments];
}
