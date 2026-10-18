// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LlamaPad",
    platforms: [.iOS(.v18)],
    products: [.library(name: "LlamaPad", targets: ["LlamaPad"])],
    dependencies: [.package(name: "LlamaPadCore", path: "..")],
    targets: [
        .binaryTarget(name: "LlamaNative", path: "Frameworks/LlamaNative.xcframework"),
        .target(name: "LlamaPad", dependencies: [
            "LlamaNative", .product(name: "LlamaPadCore", package: "LlamaPadCore")
        ], resources: [.copy("Resources/BrandMark.png")], linkerSettings: [
            .linkedLibrary("c++"), .linkedFramework("Accelerate"),
            .linkedFramework("Metal"), .linkedFramework("MetalKit"), .linkedFramework("Foundation")
        ])
    ]
)
