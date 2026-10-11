// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ScanKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ScanKit", targets: ["ScanKit"]),
        .executable(name: "scankit", targets: ["ScanKitCLI"]),
    ],
    targets: [
        .target(name: "ScanKit"),
        // Not named "scankit": macOS file systems are case-insensitive, so Sources/scankit would be Sources/ScanKit.
        .executableTarget(name: "ScanKitCLI", dependencies: ["ScanKit"]),
        .testTarget(name: "ScanKitTests", dependencies: ["ScanKit"]),
    ]
)
