// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ActionRing",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "ActionRing",
            targets: ["ActionRing"]
        )
    ],
    targets: [
        .executableTarget(
            name: "ActionRing",
            path: "Sources/ActionRing"
        )
    ]
)
