#include <sshfling/sshfling.h>

int main(int argc, char **argv) {
    return sshfling_run((size_t)(argc - 1), (const char *const *)(argv + 1));
}
