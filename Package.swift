// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Titik",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "titik", targets: ["Titik"]),
        .library(name: "TitikCore", targets: ["TitikCore"]),
        .library(name: "TitikKeymap", targets: ["TitikKeymap"]),
        .library(name: "TitikParser", targets: ["TitikParser"]),
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
            name: "TitikPlugins",
            dependencies: ["TitikCore"],
            exclude: ["include"]
        ),
        .target(
            name: "TitikUI",
            dependencies: ["TitikCore", "TitikKeymap"]
        ),
        .target(
            name: "TitikSearch",
            dependencies: ["TitikCore", "TitikParser", "TitikPlugins"]
        ),
        .target(
            name: "TitikPlatform",
            dependencies: ["TitikCore", "TitikKeymap", "TitikUI", "TitikSearch", "TitikPlugins", "TitikParser"]
        ),
        .executableTarget(
            name: "Titik",
            dependencies: ["TitikCore", "TitikPlatform", "TitikKeymap", "TitikSearch", "TitikPlugins", "TitikUI"]
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
                "TitikPlatform"
            ],
            swiftSettings: [
                .unsafeFlags(["-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-framework", "Testing",
                    "-Xlinker", "-rpath", "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath", "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"
                ])
            ]
        )
    ]
)
