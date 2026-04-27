// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LedgerMemiOS",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "LedgerMemiOS", targets: ["LedgerMemiOS"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "LedgerMemiOS",
            path: "Sources/LedgerMemiOS",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "LedgerMemiOSTests",
            dependencies: ["LedgerMemiOS"],
            path: "Tests/LedgerMemiOSTests"
        ),
    ]
)
