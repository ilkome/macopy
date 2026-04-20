// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ListTestSwiftUI",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "ListTestSwiftUI", targets: ["ListTestSwiftUI"])
    ],
    targets: [
        .executableTarget(
            name: "ListTestSwiftUI",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
