// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WalletCore",
    platforms: [
        .iOS(.v14),
        .macOS(.v12)
    ],
    products: [
        .library(name: "WalletCore", targets: ["WalletCore"]),
        .library(name: "SwiftProtobuf", targets: ["SwiftProtobuf"])
    ],
    dependencies: [],
    targets: [
        .binaryTarget(
            name: "WalletCore",
            url: "https://github.com/trustwallet/wallet-core/releases/download/4.0.38/WalletCore.xcframework.zip",
            checksum: "3aafb8d602b30626ac5c603b5f6a0e4a6d3067d7b0013e350b712715c58ee925"
        ),
        .binaryTarget(
            name: "SwiftProtobuf",
            url: "https://github.com/trustwallet/wallet-core/releases/download/4.0.38/SwiftProtobuf.xcframework.zip",
            checksum: "9d62edf09cf9a6e049ea686c82f9c55160182a898b3083506418821390426768"
        )
    ]
)
