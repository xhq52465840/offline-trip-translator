// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TripCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "TripCore", targets: ["TripCore"])],
    targets: [
        .target(name: "TripCore"),
        .testTarget(name: "TripCoreTests", dependencies: ["TripCore"]),
    ]
)
