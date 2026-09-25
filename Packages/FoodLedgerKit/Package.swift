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
        .library(name: "FoodLedgerPresentation", targets: ["FoodLedgerPresentation"]),
        .library(name: "FoodGenericSearch", targets: ["FoodGenericSearch"]),
        .library(name: "FoodBarcodeCapture", targets: ["FoodBarcodeCapture"]),
        .library(name: "FoodLedgerArchive", targets: ["FoodLedgerArchive"]),
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
            name: "FoodLedgerPresentation",
            dependencies: ["FoodLedgerDomain", "FoodLedgerApplication"]
        ),
        .target(
            name: "FoodGenericSearch",
            dependencies: ["FoodLedgerDomain", "FoodLedgerApplication"],
            resources: [.copy("Resources")]
        ),
        .target(
            name: "FoodBarcodeCapture",
            dependencies: ["FoodLedgerDomain", "FoodLedgerApplication"]
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
            name: "FoodLedgerArchive",
            dependencies: ["FoodLedgerApplication", "FoodLedgerGRDB"]
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
            name: "FoodLedgerApplicationTests",
            dependencies: [
                "FoodLedgerDomain",
                "FoodLedgerApplication",
                "FoodLedgerTestSupport"
            ]
        ),
        .testTarget(
            name: "FoodGenericSearchTests",
            dependencies: [
                "FoodLedgerDomain",
                "FoodLedgerApplication",
                "FoodGenericSearch",
                "FoodLedgerTestSupport"
            ]
        ),
        .testTarget(
            name: "FoodLedgerPresentationTests",
            dependencies: ["FoodLedgerDomain", "FoodLedgerApplication", "FoodLedgerPresentation", "FoodLedgerTestSupport"]
        ),
        .testTarget(
            name: "FoodLedgerContractTests",
            dependencies: [
                "FoodLedgerDomain",
                "FoodLedgerApplication",
                "FoodLedgerArchive",
                "FoodLedgerGRDB",
                "FoodLedgerTestSupport",
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
