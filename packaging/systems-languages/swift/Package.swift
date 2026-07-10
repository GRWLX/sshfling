// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SSHFling",
    products: [
        .library(name: "SSHFling", targets: ["SSHFling"]),
        .executable(name: "sshfling-swift", targets: ["sshfling"]),
    ],
    targets: [
        .target(
            name: "CSSHFling",
            path: "Sources/CSSHFLing",
            publicHeadersPath: "include"
        ),
        .target(name: "SSHFling", dependencies: ["CSSHFling"]),
        .executableTarget(name: "sshfling", dependencies: ["SSHFling"]),
    ]
)
