// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "walletcore",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "walletcore",
            targets: ["TrustWalletCore"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.26.0"),
    ],
    targets: [
        .binaryTarget(
            name: "TrustWalletCore",
            path: "Frameworks/TrustWalletCore.xcframework"
        )
    ]
)
