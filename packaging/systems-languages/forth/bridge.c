#include <gforth/0.7.3/libcc.h>

#include <stdint.h>

#include "sshfling_launcher.h"

void sshfling_gforth_version(GFORTH_ARGS) {
    Cell *stack = gforth_SP;

    stack -= 1;
    stack[0] = (Cell)(uintptr_t)sshfling_launcher_version();
    gforth_SP = stack;
}

void sshfling_gforth_run(GFORTH_ARGS) {
    Cell *stack = gforth_SP;
    const size_t count = (size_t)stack[1];
    const char *const *arguments = (const char *const *)(uintptr_t)stack[0];

    stack[1] = (Cell)sshfling_launcher_run(count, arguments);
    gforth_SP = stack + 1;
}
