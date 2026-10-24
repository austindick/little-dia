// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LittleDia",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "LittleDia", targets: ["LittleDia"]),
        .executable(name: "littledia-host", targets: ["littledia-host"]),
    ],
    targets: [
        .target(name: "LittleDiaCore"),
        .executableTarget(name: "LittleDia", dependencies: ["LittleDiaCore"]),
        .executableTarget(name: "littledia-host", dependencies: ["LittleDiaCore"]),
        .testTarget(name: "LittleDiaCoreTests", dependencies: ["LittleDiaCore"]),
    ],
    swiftLanguageModes: [.v5]
)
