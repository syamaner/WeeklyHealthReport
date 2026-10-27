// swift-tools-version: 6.1

import PackageDescription

// E13 qualification of docs/label-photo-ai-prefill-v1.md (#316, 17.21): the one-off paid run of
// the live label photo route, through the app's own preparer, request, attempt, read session and
// live transport. Nothing here is linked into the app.
let package = Package(
    name: "LabelPhotoE13",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../Packages/FoodLedgerKit")],
    targets: [
        .executableTarget(
            name: "label-photo-e13",
            dependencies: [
                .product(name: "FoodLedgerApplication", package: "FoodLedgerKit"),
                .product(name: "FoodLabelPhotoCapture", package: "FoodLedgerKit"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
