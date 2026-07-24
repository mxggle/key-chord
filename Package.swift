// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "KeyChord",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "KeyChord", targets: ["KeyChord"])
    ],
    targets: [
        .executableTarget(
            name: "KeyChord",
            path: "Sources/KeyChord"
        )
    ]
)
