// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "SoloCore", platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "SoloCore", targets: ["SoloCore"])],
    targets: [.target(name: "SoloCore"),
              .testTarget(name: "SoloCoreTests", dependencies: ["SoloCore"], resources: [.copy("Fixtures")])]
)
