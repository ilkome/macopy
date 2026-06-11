// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "MaCopy",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MaCopy", targets: ["MaCopy"])
    ],
    dependencies: [
        .package(url: "https://github.com/krisk/fuse-swift.git", from: "1.4.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
        .package(url: "https://github.com/sqlcipher/GRDB.swift.git", from: "7.10.0")
    ],
    targets: [
        .executableTarget(
            name: "MaCopy",
            dependencies: [
                .product(name: "Fuse", package: "fuse-swift"),
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "MaCopyTests",
            dependencies: ["MaCopy"],
            path: "Tests/MaCopyTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
