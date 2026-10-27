// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RKG68Mac",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "RKCore", targets: ["RKCore"]),
        .executable(name: "rkg68", targets: ["rkg68"]),
        .executable(name: "RKG68App", targets: ["RKG68App"]),
    ],
    targets: [
        .target(
            name: "RKCore",
            resources: [.copy("Resources/rk")]
        ),
        .executableTarget(
            name: "rkg68",
            dependencies: ["RKCore"]
        ),
        .executableTarget(
            name: "RKG68App",
            dependencies: ["RKCore"]
        ),
    ]
)
