#ifndef SSHFLING_ASSEMBLY_H
#define SSHFLING_ASSEMBLY_H

#include <stddef.h>

const char *sshfling_assembly_version(void);
int sshfling_assembly_run(size_t argc, const char *const argv[]);

#endif
