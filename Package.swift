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
    targets: [
        .target(
            name: "TitikCore",
            dependencies: []
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
            dependencies: ["TitikCore", "TitikKeymap", "TitikUI"]
        ),
        .target(
            name: "TitikPlugins",
            dependencies: ["TitikCore", "TitikPluginKit"]
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
            name: "TitikTests",
            dependencies: [
                "TitikCore",
                "TitikKeymap",
                "TitikParser",
                "TitikPlugins",
                "TitikUI",
                "TitikSearch",
                "TitikPlatform",
                "TitikPluginKit"
            ]
        ),
        .testTarget(
            name: "TitikPluginKitTests",
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
    ]
)
