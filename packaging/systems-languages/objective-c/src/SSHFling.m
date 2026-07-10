#import <SSHFling/SSHFling.h>

#include "sshfling_launcher.h"

@implementation SSHFling

+ (const char *)version {
    return sshfling_launcher_version();
}

+ (int)runWithArgumentCount:(size_t)count arguments:(const char *const [])arguments {
    return sshfling_launcher_run(count, arguments);
}

@end
