// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "DriveExportKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "DriveExportKit", targets: ["DriveExportKit"])
    ],
    targets: [
        .target(name: "DriveExportKit")
    ],
    swiftLanguageVersions: [.v5]
)
