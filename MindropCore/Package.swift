// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MindropCore",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v15), .watchOS(.v9)],
    products: [
        .library(name: "MindropCore", targets: ["MindropCore"]),
        .library(name: "MindropSaveUI", targets: ["MindropSaveUI"]),
        .library(name: "MindropIntents", targets: ["MindropIntents"]),
        .library(name: "MindropWidgetData", targets: ["MindropWidgetData"]),
    ],
    targets: [
        .target(name: "MindropCore"),
        .target(
            name: "MindropSaveUI",
            dependencies: ["MindropCore"],
            resources: [.process("Localizable.xcstrings")]
        ),
        .target(name: "MindropIntents"),
        .target(name: "MindropWidgetData"),
        .testTarget(name: "MindropCoreTests", dependencies: ["MindropCore", "MindropWidgetData"]),
    ]
)
