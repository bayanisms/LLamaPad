// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LlamaPadCore",
    platforms: [.macOS(.v13), .iOS(.v18)],
    products: [.library(name: "LlamaPadCore", targets: ["LlamaPadCore"])],
    targets: [
        .target(name: "LlamaPadCore", path: "Core")
    ]
)
