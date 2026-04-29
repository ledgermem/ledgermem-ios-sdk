// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MnemoiOS",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "MnemoiOS", targets: ["MnemoiOS"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "MnemoiOS",
            path: "Sources/MnemoiOS",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "MnemoiOSTests",
            dependencies: ["MnemoiOS"],
            path: "Tests/MnemoiOSTests"
        ),
    ]
)
