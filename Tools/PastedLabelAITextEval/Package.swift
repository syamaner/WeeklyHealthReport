// swift-tools-version: 6.1

import PackageDescription

// Pasted label AI text evaluation (docs/pasted-label-ai-text-v1.md 5, #416). A1: the evaluation
// case format `pasted-label-ai-text-eval-case-v1`, the converters from the Taiwan reader v3 and UK
// transcription schemas, and the committed bar `bar-v1.json`. No network, no label text: every
// real file stays in the private folder outside the repository. A2 adds the send and score CLI.
let package = Package(
    name: "PastedLabelAITextEval",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "PastedLabelAITextEvalCore"),
        .testTarget(name: "PastedLabelAITextEvalCoreTests", dependencies: ["PastedLabelAITextEvalCore"])
    ],
    swiftLanguageModes: [.v6]
)
