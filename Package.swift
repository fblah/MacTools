// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "DMonte",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "DMonteCore",
            targets: ["DMonteCore"]
        ),
        .executable(
            name: "DMonte",
            targets: ["DMonte"]
        ),
        .executable(
            name: "DMonteSystemMonitor",
            targets: ["DMonteSystemMonitor"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.2")
    ],
    targets: [
        .target(
            name: "DMonteCore",
            path: "Sources/DMonteCore"
        ),
        .executableTarget(
            name: "DMonte",
            dependencies: [
                "DMonteCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/DMonteApp"
        ),
        .executableTarget(
            name: "DMonteSystemMonitor",
            dependencies: [
                "DMonteCore"
            ],
            path: "Sources/DMonteSystemMonitorApp"
        )
    ]
)
