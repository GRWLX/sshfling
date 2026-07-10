// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SSHFlingConsumer",
    dependencies: [
        .package(path: "../install"),
    ],
    targets: [
        .executableTarget(
            name: "SSHFlingConsumer",
            dependencies: [
                .product(name: "SSHFling", package: "SSHFling"),
            ]
        ),
    ]
)
