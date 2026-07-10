import SSHFling

#if canImport(Glibc)
import Glibc
#else
import Darwin
#endif

exit(SSHFling.run(Array(CommandLine.arguments.dropFirst())))
