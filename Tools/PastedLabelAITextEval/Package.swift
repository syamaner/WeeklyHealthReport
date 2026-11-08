// swift-tools-version: 6.1

import PackageDescription

// Pasted label AI text evaluation (docs/pasted-label-ai-text-v1.md 5, #416). A1: the evaluation
// case format `pasted-label-ai-text-eval-case-v1`, the converters from the Taiwan reader v3 and UK
// transcription schemas, and the committed bar `bar-v1.json`. A2: the `PastedLabelAITextEval` CLI
// (`send` and `score`) over the shipped request builder, reader and checks, the spend reservation,
// the response cache and the legacy converter. No network: A2 wires only a fake transport, and
// every real file stays in the private folder outside the repository.
let package = Package(
    name: "PastedLabelAITextEval",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../Packages/FoodLedgerKit")],
    targets: [
        // Pure: Foundation and CryptoKit only (check-boundaries.sh).
        .target(name: "PastedLabelAITextEvalCore"),
        // The harness: the shipped adapters, the fake transport, the ledger and the cache.
        .target(
            name: "PastedLabelAITextEvalHarness",
            dependencies: [
                "PastedLabelAITextEvalCore",
                .product(name: "FoodLedgerApplication", package: "FoodLedgerKit"),
                .product(name: "FoodLabelPhotoCapture", package: "FoodLedgerKit"),
                .product(name: "FoodLabelTextAIReading", package: "FoodLedgerKit"),
            ]
        ),
        .executableTarget(name: "PastedLabelAITextEval", dependencies: ["PastedLabelAITextEvalHarness", "PastedLabelAITextEvalCore"]),
        .testTarget(name: "PastedLabelAITextEvalCoreTests", dependencies: ["PastedLabelAITextEvalCore"]),
        .testTarget(
            name: "PastedLabelAITextEvalHarnessTests",
            dependencies: [
                "PastedLabelAITextEvalHarness", "PastedLabelAITextEvalCore",
                .product(name: "FoodLedgerApplication", package: "FoodLedgerKit"),
                .product(name: "FoodLabelPhotoCapture", package: "FoodLedgerKit"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
