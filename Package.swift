// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "JevAgent",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "JevAgent", targets: ["JevAgent"]), .executable(name: "JevEval", targets: ["JevEval"]), .library(name: "JevCore", targets: ["JevCore"])],
    targets: [
        .target(name: "JevCore"),
        .executableTarget(name: "JevEval", dependencies: ["JevCore"]),
        .executableTarget(name: "JevAgent", dependencies: ["JevCore"], resources: [.copy("Resources")]),
        .testTarget(name: "JevCoreTests", dependencies: ["JevCore"])
    ]
)
