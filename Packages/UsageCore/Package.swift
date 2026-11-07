// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "UsageCore",
    platforms: [.macOS("27.0")],
    products: [.library(name: "UsageCore", targets: ["UsageCore"])],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-subprocess.git", from: "1.0.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.2"),
    ],
    targets: [
        .target(name: "UsageCore", dependencies: [
            .product(name: "Subprocess", package: "swift-subprocess"),
            .product(name: "Yams", package: "Yams"),
        ]),
        .testTarget(name: "UsageCoreTests", dependencies: ["UsageCore"], resources: [.copy("Fixtures")]),
    ],
    swiftLanguageModes: [.v6]
)
