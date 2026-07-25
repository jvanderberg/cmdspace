// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CmdSpace",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "CmdSpace", targets: ["CmdSpace"])
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite"
        ),
        .executableTarget(
            name: "CmdSpace",
            dependencies: ["CSQLite"],
            path: "Sources/CmdSpace",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "CmdSpaceTests",
            dependencies: ["CmdSpace"],
            path: "Tests/CmdSpaceTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
