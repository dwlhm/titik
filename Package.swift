// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Titik",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "titik", targets: ["Titik"]),
        .executable(name: "titik-worker", targets: ["TitikWorker"]),
        .library(name: "TitikCore", targets: ["TitikCore"]),
        .library(name: "TitikKeymap", targets: ["TitikKeymap"]),
        .library(name: "TitikParser", targets: ["TitikParser"]),
        .library(name: "TitikPluginKit", targets: ["TitikPluginKit"]),
        .library(name: "TitikPlugins", targets: ["TitikPlugins"]),
        .library(name: "TitikUI", targets: ["TitikUI"]),
        .library(name: "TitikSearch", targets: ["TitikSearch"]),
        .library(name: "TitikPlatform", targets: ["TitikPlatform"])
    ],
    dependencies: [
        .package(url: "https://github.com/nicklockwood/Expression.git", from: "0.13.0"),
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.5.0")
    ],
    targets: [
        .target(
            name: "TitikCore",
            dependencies: [
                .product(name: "Expression", package: "Expression")
            ]
        ),
        .target(
            name: "TitikKeymap",
            dependencies: ["TitikCore"]
        ),
        .target(
            name: "TitikParser",
            dependencies: []
        ),
        .target(
            name: "TitikUI",
            dependencies: ["TitikCore", "TitikKeymap"]
        ),
        .target(
            name: "TitikPluginKit",
            dependencies: [
                "TitikCore",
                "TitikKeymap",
                "TitikUI",
                .product(name: "Markdown", package: "swift-markdown")
            ]
        ),
        .target(
            name: "TitikPlugins",
            dependencies: ["TitikCore", "TitikKeymap", "TitikUI", "TitikPluginKit", "TitikParser"]
        ),
        .target(
            name: "TitikSearch",
            dependencies: ["TitikCore", "TitikParser", "TitikPlugins", "TitikPluginKit"]
        ),
        .target(
            name: "TitikPlatform",
            dependencies: ["TitikCore", "TitikKeymap", "TitikUI", "TitikSearch", "TitikPlugins", "TitikParser", "TitikPluginKit"]
        ),
        .executableTarget(
            name: "Titik",
            dependencies: ["TitikCore", "TitikPlatform", "TitikKeymap", "TitikSearch", "TitikPlugins", "TitikUI", "TitikPluginKit"]
        ),
        .executableTarget(
            name: "TitikWorker",
            dependencies: ["TitikCore", "TitikPluginKit", "TitikPlugins"]
        ),
        .testTarget(
            name: "TitikParserTests",
            dependencies: [
                "TitikParser"
            ]
        ),
        .testTarget(
            name: "TitikCoreTests",
            dependencies: [
                "TitikCore",
                "TitikParser"
            ]
        ),
        .testTarget(
            name: "TitikKeymapTests",
            dependencies: [
                "TitikCore",
                "TitikKeymap"
            ]
        ),
        .testTarget(
            name: "TitikSearchTests",
            dependencies: [
                "TitikCore",
                "TitikParser",
                "TitikSearch",
                "TitikPluginKit",
                "TitikPlugins"
            ]
        ),
        .testTarget(
            name: "TitikPluginKitTests",
            dependencies: [
                "TitikCore",
                "TitikKeymap",
                "TitikPluginKit"
            ]
        ),
        .testTarget(
            name: "TitikPluginsTests",
            dependencies: [
                "TitikCore",
                "TitikKeymap",
                "TitikUI",
                "TitikPluginKit",
                "TitikPlugins",
                "TitikParser"
            ]
        ),
        .testTarget(
            name: "PluginHostTests",
            dependencies: [
                "TitikCore",
                "TitikKeymap",
                "TitikUI",
                "TitikPluginKit",
                "TitikPlugins",
                "TitikPlatform"
            ]
        ),
        .testTarget(
            name: "TitikE2ETests",
            dependencies: [
                "TitikCore",
                "TitikKeymap",
                "TitikUI",
                "TitikSearch",
                "TitikParser",
                "TitikPluginKit",
                "TitikPlugins",
                "TitikPlatform"
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
