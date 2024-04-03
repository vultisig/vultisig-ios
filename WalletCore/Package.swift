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
            url: "https://github.com/trustwallet/wallet-core/releases/download/4.0.32/WalletCore.xcframework.zip",
            checksum: "1fc695459be46701d8c00a5c4972dd449549b73c5bb9f4dce5d17c5754963af2"
        ),
        .binaryTarget(
            name: "SwiftProtobuf",
            url: "https://github.com/trustwallet/wallet-core/releases/download/4.0.32/SwiftProtobuf.xcframework.zip",
            checksum: "c49c2169882406f05f5d602744f1be806a618be20907f05dd5b0aafed441ee76"
        )
    ]
)
