// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "GramPotLogic",
    products: [
        .library(name: "GramPotLogic", targets: ["GramPotLogic"]),
    ],
    targets: [
        .target(name: "GramPotLogic"),
        .testTarget(
            name: "GramPotLogicTests",
            dependencies: ["GramPotLogic"]
        ),
    ]
)
