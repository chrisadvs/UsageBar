// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TokenUsageWidget",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "TokenUsageWidget",
            dependencies: []),
        .testTarget(
            name: "TokenUsageWidgetTests",
            dependencies: ["TokenUsageWidget"]),
    ]
)
