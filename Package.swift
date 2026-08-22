// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "JasonUI",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "JasonUI", targets: ["JasonUI"])
    ],
    targets: [
        .executableTarget(name: "JasonUI"),
        .testTarget(name: "JasonUITests", dependencies: ["JasonUI"])
    ]
)

