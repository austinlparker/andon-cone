// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AndonCone",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .executable(name: "AndonCone", targets: ["AndonCone"])
    ],
    dependencies: [
        .package(url: "https://github.com/embrace-io/embrace-apple-sdk.git", from: "6.18.0")
    ],
    targets: [
        .executableTarget(
            name: "AndonCone",
            dependencies: [
                .product(name: "EmbraceIO", package: "embrace-apple-sdk", condition: .when(platforms: [.iOS]))
            ],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("AVKit")
            ]
        )
    ]
)
