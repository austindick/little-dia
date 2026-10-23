// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LilBrowWow",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "LilBrowWow", targets: ["LilBrowWow"]),
        .executable(name: "lilbrow-host", targets: ["lilbrow-host"]),
    ],
    targets: [
        .target(name: "LilBrowCore"),
        .executableTarget(name: "LilBrowWow", dependencies: ["LilBrowCore"]),
        .executableTarget(name: "lilbrow-host", dependencies: ["LilBrowCore"]),
        .testTarget(name: "LilBrowCoreTests", dependencies: ["LilBrowCore"]),
    ],
    swiftLanguageModes: [.v5]
)
