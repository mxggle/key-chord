// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AppSwitcher",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AppSwitcher", targets: ["AppSwitcher"])
    ],
    targets: [
        .executableTarget(
            name: "AppSwitcher",
            path: "Sources/AppSwitcher"
        )
    ]
)
