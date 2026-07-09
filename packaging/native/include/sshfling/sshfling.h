#ifndef SSHFLING_SSHFLING_H
#define SSHFLING_SSHFLING_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

const char *sshfling_version(void);
int sshfling_run(size_t argc, const char *const argv[]);
int sshfling_run_with_python(const char *python, size_t argc, const char *const argv[]);

#ifdef __cplusplus
}
#endif

#endif
