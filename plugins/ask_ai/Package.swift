// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AskAIPlugin",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "AskAIPlugin",
            type: .dynamic,
            targets: ["AskAIPluginModule"]
        )
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .target(
            name: "AskAIPluginModule",
            dependencies: [
                .product(name: "TitikCore", package: "titik"),
                .product(name: "TitikKeymap", package: "titik"),
                .product(name: "TitikUI", package: "titik"),
                .product(name: "TitikPluginKit", package: "titik")
            ],
            path: "Sources"
        )
    ]
)
