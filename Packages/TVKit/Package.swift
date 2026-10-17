// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TVKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "TVKit", targets: ["TVKit"]),
    ],
    targets: [
        .target(name: "TVKit"),
        .testTarget(name: "TVKitTests", dependencies: ["TVKit"]),
    ]
)
