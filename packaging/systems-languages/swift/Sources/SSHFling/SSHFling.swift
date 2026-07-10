import CSSHFling

#if canImport(Glibc)
import Glibc
#else
import Darwin
#endif

public enum SSHFling {
    public static let version = "0.0.0"

    public static var runtimeVersion: String {
        String(cString: sshfling_launcher_version())
    }

    @discardableResult
    public static func run(_ arguments: [String]) -> Int32 {
        let storage = arguments.map { strdup($0) }
        defer {
            for pointer in storage {
                free(pointer)
            }
        }
        guard storage.allSatisfy({ $0 != nil }) else {
            return 127
        }

        var pointers: [UnsafePointer<CChar>?] = storage.map { pointer in
            pointer.map { UnsafePointer($0) }
        }
        return pointers.withUnsafeBufferPointer { buffer in
            sshfling_launcher_run(buffer.count, buffer.baseAddress)
        }
    }
}
