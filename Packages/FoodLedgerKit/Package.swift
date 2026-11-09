// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "FoodLedgerKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .executable(name: "FoodProposalProbe", targets: ["FoodProposalProbe"]),
        .executable(name: "NutritionLabelTextParse", targets: ["NutritionLabelTextParse"]),
        .library(name: "NutritionLabelParsing", targets: ["NutritionLabelParsing"]),
        .library(name: "FoodLedgerDomain", targets: ["FoodLedgerDomain"]),
        .library(name: "FoodLedgerApplication", targets: ["FoodLedgerApplication"]),
        .library(name: "FoodLedgerPresentation", targets: ["FoodLedgerPresentation"]),
        .library(name: "FoodGenericSearch", targets: ["FoodGenericSearch"]),
        .library(name: "FoodInventoryImport", targets: ["FoodInventoryImport"]),
        .library(name: "FoodBarcodeCapture", targets: ["FoodBarcodeCapture"]),
        .library(name: "FoodLabelTextCapture", targets: ["FoodLabelTextCapture"]),
        .library(name: "FoodLabelPhotoCapture", targets: ["FoodLabelPhotoCapture"]),
        .library(name: "FoodLabelTextAIReading", targets: ["FoodLabelTextAIReading"]),
        .library(name: "FoodLabelPhotoUI", targets: ["FoodLabelPhotoUI"]),
        .library(name: "FoodLedgerArchive", targets: ["FoodLedgerArchive"]),
        .library(name: "FoodLedgerGRDB", targets: ["FoodLedgerGRDB"]),
        .library(name: "FoodLedgerTestSupport", targets: ["FoodLedgerTestSupport"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", exact: "2.13.9")
    ],
    targets: [
        .executableTarget(name: "FoodProposalProbe", dependencies: ["FoodGenericSearch", "FoodLedgerApplication", "FoodLedgerDomain"], path: "Tools/FoodProposalProbe"),
        .executableTarget(name: "NutritionLabelTextParse", dependencies: ["NutritionLabelParsing"], path: "Tools/NutritionLabelTextParse"),
        .target(name: "FoodLedgerDomain"),
        // Pure label-text parser (#255) and the pasted-label parity ports (#93); Foundation only,
        // no app dependency. Resources: the frozen decline gate v2 tables.
        .target(name: "NutritionLabelParsing", resources: [.copy("Resources")]),
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
            dependencies: ["FoodLedgerDomain", "FoodLedgerApplication", .product(name: "SwiftSoup", package: "SwiftSoup")],
            resources: [.copy("Resources")]
        ),
        .target(
            name: "FoodBarcodeCapture",
            dependencies: ["FoodLedgerDomain", "FoodLedgerApplication"]
        ),
        // Pasted nutrition label reader (#93, decision 10): the only product target that may
        // depend on NutritionLabelParsing; wired at the app's composition root.
        // UK English pasted label reader (#371 P2a, docs/pasted-nutrition-label-uk-english-v1-p2.md):
        // normalisation and guard rules around the frozen parser v3, which it reaches only through
        // its public API; no library product, used only by FoodLabelTextCapture.
        .target(name: "UKNutritionLabelParsing", dependencies: ["NutritionLabelParsing"]),
        .target(
            name: "FoodLabelTextCapture",
            dependencies: ["FoodLedgerDomain", "FoodLedgerApplication", "NutritionLabelParsing", "UKNutritionLabelParsing"]
        ),
        // Label photo AI pre-fill reader (#316, docs/label-photo-ai-prefill-v1.md 12.1 and 17.2):
        // pure (Foundation, the application and domain, and the frozen parser rules): the value
        // matcher, the wire mapping and the reader; reached only through the capture adapter.
        .target(name: "FoodLabelPhotoReading", dependencies: ["FoodLedgerApplication", "FoodLedgerDomain", "NutritionLabelParsing"]),
        // Label photo capture adapters (#316, docs/label-photo-ai-prefill-v1.md 12.1 and 17.2): the
        // ImageIO preparer and the Vision locator; wired only at the composition root.
        .target(
            name: "FoodLabelPhotoCapture",
            dependencies: ["FoodLedgerApplication", "FoodLedgerDomain", "FoodLabelPhotoReading"],
            resources: [.copy("Resources/label-photo-instruction-v1.txt"), .copy("Resources/label-photo-wire-schema-v1.json"),
                        // Pasted label AI text route (#416 A2): prompt-v1 and the text wire schema, pinned by SHA-256.
                        .copy("Resources/pasted-label-ai-text-instruction-v1.txt"), .copy("Resources/pasted-label-ai-text-wire-schema-v1.json"),
                        // #416 A3 (revision 11): prompt-v2, selectable by the evaluation tool only; the app sends prompt-v1.
                        .copy("Resources/pasted-label-ai-text-instruction-v2.txt")]
        ),
        // Pasted label AI text reader (#416 A2, docs/pasted-label-ai-text-v1.md 11.1): pure (Foundation,
        // the application and domain, and the frozen parser rules): the text wire schema, the text
        // mapping and the reader. It never imports FoodLabelPhotoReading; wired only at the composition
        // root, and used by the evaluation tool in Tools/PastedLabelAITextEval.
        .target(name: "FoodLabelTextAIReading", dependencies: ["FoodLedgerApplication", "FoodLedgerDomain", "NutritionLabelParsing"]),
        .target(name: "FoodLabelPhotoUI", dependencies: ["FoodLedgerApplication", "FoodLedgerDomain"]),
        .target(name: "FoodInventoryImport", dependencies: ["FoodLedgerApplication", "FoodLedgerDomain"]),
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
            name: "NutritionLabelParsingTests",
            dependencies: ["NutritionLabelParsing"],
            // Parity vectors exported from the frozen Python reference (#93, pasted label PR 1).
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "FoodLabelPhotoCaptureTests",
            dependencies: ["FoodLabelPhotoCapture", "FoodLabelPhotoReading", "FoodLedgerApplication", "FoodLedgerDomain", "FoodLedgerTestSupport"]
        ),
        // Imports both readers, so the text mapping's parity with label-photo-wire-mapping-v1 is tested (11.1).
        .testTarget(
            name: "FoodLabelTextAIReadingTests",
            dependencies: ["FoodLabelTextAIReading", "FoodLabelPhotoReading", "FoodLedgerApplication", "FoodLedgerDomain", "FoodLedgerTestSupport",
                           "NutritionLabelParsing"]
        ),
        .testTarget(
            name: "FoodLabelPhotoReadingTests",
            dependencies: ["FoodLabelPhotoReading", "FoodLedgerApplication", "FoodLedgerDomain", "NutritionLabelParsing"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "FoodLabelTextCaptureTests",
            dependencies: [
                "FoodLabelTextCapture",
                "FoodLedgerApplication",
                "FoodLedgerDomain",
                "FoodLedgerTestSupport",
                "NutritionLabelParsing",
                "UKNutritionLabelParsing"
            ]
        ),
        .testTarget(
            name: "UKNutritionLabelParsingTests",
            dependencies: ["NutritionLabelParsing", "UKNutritionLabelParsing"]
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
            dependencies: ["FoodLedgerDomain", "FoodLedgerApplication", "FoodLedgerPresentation", "FoodLedgerTestSupport", "FoodGenericSearch"]
        ),
        .testTarget(
            name: "FoodLedgerContractTests",
            dependencies: [
                "FoodGenericSearch",
                "FoodLedgerDomain",
                "FoodLedgerApplication",
                "FoodLedgerArchive",
                "FoodLedgerGRDB",
                "FoodInventoryImport",
                "FoodLedgerTestSupport",
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            resources: [.copy("Fixtures")]
        )
    ],
    swiftLanguageModes: [.v6]
)
