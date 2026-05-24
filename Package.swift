// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "MacTools",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "MacTools",
            targets: ["MacTools"]
        )
    ],
    targets: [
        .executableTarget(
            name: "MacTools",
            path: "Sources/MacTools"
        )
    ]
)
