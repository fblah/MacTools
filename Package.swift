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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.2")
    ],
    targets: [
        .executableTarget(
            name: "MacTools",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/MacTools"
        )
    ]
)
