// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Nimbus",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Nimbus", path: "Sources/Nimbus"),
        .testTarget(name: "NimbusTests", dependencies: ["Nimbus"], path: "Tests/NimbusTests"),
    ]
)
