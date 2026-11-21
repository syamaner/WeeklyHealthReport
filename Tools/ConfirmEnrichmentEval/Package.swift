// swift-tools-version: 6.1

import PackageDescription

// Confirm enrichment evaluation (docs/confirm-enrichment-openrouter-v1-phase.md sections 3.3 item 5, 8 and
// 9; docs/confirm-enrichment-openrouter-v1.md section 12 and CE-T15, #549). PR 3: the private case list
// format, case hashes and set manifests, the section 11.1a preflight, the CE-T15 spend ledger and the
// run loop over the app's own request builders, adapters and route checker, through a fake transport
// in tests. The scorer, bars and frozen configuration are PR 4a. Every real case, response and ledger
// stays in the owner's private evaluation folder outside the repository; the owner runs the tool.
let package = Package(
    name: "ConfirmEnrichmentEval",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../Packages/FoodLedgerKit")],
    targets: [
        // Pure: no URL loading and no live transport (check-boundaries.sh).
        .target(
            name: "ConfirmEnrichmentEvalCore",
            dependencies: [
                .product(name: "FoodLedgerApplication", package: "FoodLedgerKit"),
                .product(name: "FoodLedgerDomain", package: "FoodLedgerKit"),
            ]
        ),
        // The harness: the app's request builders, adapters and route checker, the fake transport, and
        // the one live-transport file.
        .target(
            name: "ConfirmEnrichmentEvalHarness",
            dependencies: [
                "ConfirmEnrichmentEvalCore",
                .product(name: "FoodLedgerApplication", package: "FoodLedgerKit"),
                .product(name: "FoodLedgerDomain", package: "FoodLedgerKit"),
                .product(name: "FoodConfirmEnrichment", package: "FoodLedgerKit"),
                .product(name: "FoodGenericSearch", package: "FoodLedgerKit"),
            ]
        ),
        .executableTarget(name: "ConfirmEnrichmentEval", dependencies: ["ConfirmEnrichmentEvalHarness", "ConfirmEnrichmentEvalCore"]),
        .testTarget(name: "ConfirmEnrichmentEvalCoreTests", dependencies: ["ConfirmEnrichmentEvalCore"]),
        .testTarget(
            name: "ConfirmEnrichmentEvalHarnessTests",
            dependencies: [
                "ConfirmEnrichmentEvalHarness", "ConfirmEnrichmentEvalCore",
                .product(name: "FoodLedgerApplication", package: "FoodLedgerKit"),
                .product(name: "FoodLedgerDomain", package: "FoodLedgerKit"),
                .product(name: "FoodConfirmEnrichment", package: "FoodLedgerKit"),
                .product(name: "FoodGenericSearch", package: "FoodLedgerKit"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
