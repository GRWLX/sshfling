#ifndef SSHFLING_SYSTEMS_LAUNCHER_H
#define SSHFLING_SYSTEMS_LAUNCHER_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

const char *sshfling_launcher_version(void);
int sshfling_launcher_run(size_t argc, const char *const argv[]);
int sshfling_launcher_main(int argc, char *const argv[]);
int sshfling_launcher_run_nul(size_t argc, const char *arguments);
int sshfling_launcher_run_strided(size_t argc, const char *arguments, size_t stride);
int sshfling_launcher_run_process_arguments(void);

#ifdef __cplusplus
}
#endif

#endif
