#import <SSHFling/SSHFling.h>

int main(int argc, char **argv) {
    return [SSHFling
        runWithArgumentCount:(size_t)(argc - 1)
        arguments:(const char *const *)(argv + 1)];
}
