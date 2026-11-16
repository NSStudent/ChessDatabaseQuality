// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ChessDatabaseQuality",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "ChessDatabaseQuality", targets: ["ChessDatabaseQuality"]),
        .executable(name: "cdq", targets: ["cdq"]),
    ],
    dependencies: [
        .package(url: "https://github.com/NSStudent/fischer-core.git", from: "0.4.0"),
    ],
    targets: [
        .target(
            name: "ChessDatabaseQuality",
            dependencies: [
                .product(name: "FischerCore", package: "fischer-core"),
            ]
        ),
        .executableTarget(
            name: "cdq",
            dependencies: ["ChessDatabaseQuality"]
        ),
        .testTarget(
            name: "ChessDatabaseQualityTests",
            dependencies: ["ChessDatabaseQuality"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
