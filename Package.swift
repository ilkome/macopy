// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MaCopy",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "MaCopy", targets: ["MaCopy"])
    ],
    dependencies: [
        .package(url: "https://github.com/krisk/fuse-swift.git", from: "1.4.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "MaCopy",
            dependencies: [
                .product(name: "Fuse", package: "fuse-swift"),
                .product(name: "Sparkle", package: "Sparkle")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
