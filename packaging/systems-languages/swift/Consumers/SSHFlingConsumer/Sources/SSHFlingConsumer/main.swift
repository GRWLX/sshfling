import SSHFling

#if canImport(Glibc)
import Glibc
#else
import Darwin
#endif

guard CommandLine.arguments.count == 2 else {
    exit(1)
}
let expected = CommandLine.arguments[1]
guard SSHFling.version == expected, SSHFling.runtimeVersion == expected else {
    exit(1)
}
exit(SSHFling.run(["--version"]))
