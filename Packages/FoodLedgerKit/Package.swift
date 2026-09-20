// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "FoodLedgerKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "FoodLedgerDomain", targets: ["FoodLedgerDomain"]),
        .library(name: "FoodLedgerApplication", targets: ["FoodLedgerApplication"]),
        .library(name: "FoodLedgerGRDB", targets: ["FoodLedgerGRDB"]),
        .library(name: "FoodLedgerTestSupport", targets: ["FoodLedgerTestSupport"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1")
    ],
    targets: [
        .target(name: "FoodLedgerDomain"),
        .target(
            name: "FoodLedgerApplication",
            dependencies: ["FoodLedgerDomain"]
        ),
        .target(
            name: "FoodLedgerGRDB",
            dependencies: [
                "FoodLedgerDomain",
                "FoodLedgerApplication",
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .target(
            name: "FoodLedgerTestSupport",
            dependencies: ["FoodLedgerDomain", "FoodLedgerApplication"]
        ),
        .testTarget(
            name: "FoodLedgerDomainTests",
            dependencies: ["FoodLedgerDomain"]
        ),
        .testTarget(
            name: "FoodLedgerContractTests",
            dependencies: [
                "FoodLedgerDomain",
                "FoodLedgerApplication",
                "FoodLedgerGRDB",
                "FoodLedgerTestSupport",
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
