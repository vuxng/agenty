// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "UsageCore",
    platforms: [.macOS("27.0")],
    products: [.library(name: "UsageCore", targets: ["UsageCore"])],
    dependencies: [.package(url: "https://github.com/swiftlang/swift-subprocess.git", from: "1.0.0")],
    targets: [
        .target(name: "UsageCore", dependencies: [.product(name: "Subprocess", package: "swift-subprocess")]),
        .testTarget(name: "UsageCoreTests", dependencies: ["UsageCore"]),
    ],
    swiftLanguageModes: [.v6]
)
