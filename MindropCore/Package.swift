// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MindropCore",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "MindropCore", targets: ["MindropCore"]),
        .library(name: "MindropSaveUI", targets: ["MindropSaveUI"]),
    ],
    targets: [
        .target(name: "MindropCore"),
        .target(name: "MindropSaveUI", dependencies: ["MindropCore"]),
        .testTarget(name: "MindropCoreTests", dependencies: ["MindropCore"]),
    ]
)
