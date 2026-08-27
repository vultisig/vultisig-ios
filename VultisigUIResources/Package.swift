// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "VultisigUIResources",
    platforms: [
        .iOS(.v17),
        .macOS("15.0")
    ],
    products: [
        .library(
            name: "VultisigUIResources",
            targets: ["VultisigUIResources"]
        )
    ],
    targets: [
        .target(
            name: "VultisigUIResources",
            resources: [
                .process("Resources/Images.xcassets"),
                .copy("Resources/Fonts")
            ]
        ),
        .testTarget(
            name: "VultisigUIResourcesTests",
            dependencies: ["VultisigUIResources"]
        )
    ]
)
