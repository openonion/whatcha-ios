// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Whatcha",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "WhatchaCore", targets: ["WhatchaCore"])],
    targets: [
        .target(name: "WhatchaCore"),
        .testTarget(name: "WhatchaCoreTests", dependencies: ["WhatchaCore"],
                    resources: [.copy("android-wire-vector.jsonl")])
    ]
)
