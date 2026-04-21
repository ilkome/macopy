// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ListTestSwiftUI",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "ListTestSwiftUI", targets: ["ListTestSwiftUI"])
    ],
    dependencies: [
        .package(url: "https://github.com/krisk/fuse-swift.git", from: "1.4.0")
    ],
    targets: [
        .executableTarget(
            name: "ListTestSwiftUI",
            dependencies: [
                .product(name: "Fuse", package: "fuse-swift")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
