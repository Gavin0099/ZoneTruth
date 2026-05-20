// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ZoneTruth",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "ZoneTruthCore",
            targets: ["ZoneTruthCore"]
        ),
        .library(
            name: "ZoneTruthApp",
            targets: ["ZoneTruthApp"]
        ),
    ],
    targets: [
        .target(
            name: "ZoneTruthCore"
        ),
        .target(
            name: "ZoneTruthApp",
            dependencies: ["ZoneTruthCore"],
            exclude: ["Info.plist"]
        ),
        .testTarget(
            name: "ZoneTruthCoreTests",
            dependencies: ["ZoneTruthCore"]
        ),
        .testTarget(
            name: "ZoneTruthAppTests",
            dependencies: ["ZoneTruthApp", "ZoneTruthCore"],
            resources: [
                .process("Fixtures")
            ]
        ),
    ]
)
