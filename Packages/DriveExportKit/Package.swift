// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "DriveExportKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "DriveExportKit", targets: ["DriveExportKit"]),
        .library(name: "DriveExportOAuth", targets: ["DriveExportOAuth"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/openid/AppAuth-iOS.git",
            exact: "2.1.0"
        )
    ],
    targets: [
        .target(name: "DriveExportKit"),
        .target(
            name: "DriveExportOAuth",
            dependencies: [
                "DriveExportKit",
                .product(name: "AppAuth", package: "AppAuth-iOS")
            ]
        ),
        .testTarget(
            name: "DriveExportOAuthTests",
            dependencies: ["DriveExportOAuth"]
        )
    ],
    swiftLanguageVersions: [.v5]
)
