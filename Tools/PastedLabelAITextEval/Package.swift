// swift-tools-version: 6.1

import PackageDescription

// Pasted label AI text evaluation (docs/pasted-label-ai-text-v1.md 5, #416). A1: the evaluation
// case format `pasted-label-ai-text-eval-case-v1`, the converters from the Taiwan reader v3 and UK
// transcription schemas, and the committed bar `bar-v1.json`. A2: the `PastedLabelAITextEval` CLI
// (`send` and `score`) over the shipped request builder, reader and checks, the spend reservation,
// the response cache and the legacy converter, over a directory fake transport. A3: `send --live`,
// the shipped live transport (named only in `LiveTransport.swift`, check-boundaries.sh) with the key
// from the environment only and retries under the spend ledger, for the tuning runs. A3 also commits
// `bar-v2.json` (D34; `bar-v1.json` stays as history) and the freeze pins (D35, FreezePinTests). Every
// real file stays in the private folder outside the repository.
let package = Package(
    name: "PastedLabelAITextEval",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../Packages/FoodLedgerKit")],
    targets: [
        // Pure: Foundation and CryptoKit only (check-boundaries.sh).
        .target(name: "PastedLabelAITextEvalCore"),
        // The harness: the shipped adapters, the fake and live connections, the ledger and the cache.
        .target(
            name: "PastedLabelAITextEvalHarness",
            dependencies: [
                "PastedLabelAITextEvalCore",
                .product(name: "FoodLedgerApplication", package: "FoodLedgerKit"),
                .product(name: "FoodLabelPhotoCapture", package: "FoodLedgerKit"),
                .product(name: "FoodLabelTextAIReading", package: "FoodLedgerKit"),
            ]
        ),
        // The CLI names the request builder's closed prompt versions (`--prompt-version`, revision 11).
        .executableTarget(
            name: "PastedLabelAITextEval",
            dependencies: ["PastedLabelAITextEvalHarness", "PastedLabelAITextEvalCore",
                           .product(name: "FoodLabelPhotoCapture", package: "FoodLedgerKit")]
        ),
        .testTarget(name: "PastedLabelAITextEvalCoreTests", dependencies: ["PastedLabelAITextEvalCore"]),
        .testTarget(
            name: "PastedLabelAITextEvalHarnessTests",
            dependencies: [
                "PastedLabelAITextEvalHarness", "PastedLabelAITextEvalCore",
                .product(name: "FoodLedgerApplication", package: "FoodLedgerKit"),
                .product(name: "FoodLabelPhotoCapture", package: "FoodLedgerKit"),
                .product(name: "FoodLabelTextAIReading", package: "FoodLedgerKit"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
