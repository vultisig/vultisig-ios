// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Mediator",
    platforms: [
        .macOS(.v12),
        .iOS(.v14)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "Mediator",
            targets: ["Mediator"]),
    ],
    dependencies: [
        .package(url: "https://github.com/httpswift/swifter", from: "1.5.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "Mediator",
            dependencies: [.product(name: "Swifter", package: "swifter")]),
        .testTarget(
            name: "MediatorTests",
            dependencies: ["Mediator"]),
    ]
)
