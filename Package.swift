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
    targets: [
        .executableTarget(
            name: "AndonCone",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("AVKit")
            ]
        )
    ]
)
