// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MindropCore",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "MindropCore", targets: ["MindropCore"])
    ],
    targets: [
        .target(name: "MindropCore"),
        .testTarget(name: "MindropCoreTests", dependencies: ["MindropCore"])
    ]
)
