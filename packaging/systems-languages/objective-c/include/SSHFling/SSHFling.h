#ifndef SSHFLING_OBJECTIVE_C_H
#define SSHFLING_OBJECTIVE_C_H

#include <stddef.h>

__attribute__((objc_root_class))
@interface SSHFling
+ (const char *)version;
+ (int)runWithArgumentCount:(size_t)count arguments:(const char *const [])arguments;
@end

#endif
