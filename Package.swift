// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SlowVape",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SlowVapeCore"),
        .executableTarget(name: "SlowVape", dependencies: ["SlowVapeCore"]),
        .testTarget(name: "SlowVapeCoreTests", dependencies: ["SlowVapeCore"], path: "Tests")
    ]
)
