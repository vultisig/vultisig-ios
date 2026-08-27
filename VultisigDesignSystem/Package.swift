// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "VultisigDesignSystem",
    platforms: [
        .iOS(.v17),
        .macOS("15.0")
    ],
    products: [
        .library(
            name: "VultisigDesignSystem",
            targets: ["VultisigDesignSystem"]
        )
    ],
    dependencies: [
        .package(path: "../VultisigUIResources")
    ],
    targets: [
        .target(
            name: "VultisigDesignSystem",
            dependencies: [
                .product(
                    name: "VultisigUIResources",
                    package: "VultisigUIResources"
                )
            ]
        ),
        .testTarget(
            name: "VultisigDesignSystemTests",
            dependencies: ["VultisigDesignSystem"]
        )
    ]
)
