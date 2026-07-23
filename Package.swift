// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Valhalla",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Valhalla", targets: ["Valhalla"])
    ],
    targets: [
        .executableTarget(
            name: "Valhalla",
            path: "Sources/Valhalla"
        ),
        .testTarget(
            name: "ValhallaTests",
            dependencies: ["Valhalla"],
            path: "Tests/ValhallaTests"
        )
    ]
)
