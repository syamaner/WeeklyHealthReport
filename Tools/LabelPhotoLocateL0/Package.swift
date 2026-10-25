// swift-tools-version: 5.9

import PackageDescription

// Phase L0 of docs/label-photo-ai-prefill-v1.md (#316): offline, on-device locate-rate
// measurement. No network. The matcher target is the code L1 carries into the app package.
let package = Package(
    name: "LabelPhotoLocateL0",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "LabelValueMatching"),
        .executableTarget(name: "label-photo-locate-l0", dependencies: ["LabelValueMatching"]),
        .testTarget(name: "LabelValueMatchingTests", dependencies: ["LabelValueMatching"])
    ]
)
