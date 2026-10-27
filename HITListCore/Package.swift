// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "HITListCore",
    platforms: [.iOS(.v17), .macOS(.v14), .watchOS(.v10)],
    products: [
        .library(name: "HITListCore", targets: ["HITListCore"]),
    ],
    targets: [
        .target(name: "HITListCore"),
        .testTarget(name: "HITListCoreTests", dependencies: ["HITListCore"]),
    ]
)
