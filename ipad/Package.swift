// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AirCode",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "AirCodeClient", targets: ["AirCodeClient"]),
        .executable(name: "AirCodePreview", targets: ["AirCodePreview"]),
        .executable(name: "AirCodeIntegrationSmoke", targets: ["AirCodeIntegrationSmoke"])
    ],
    dependencies: [
        .package(url: "https://github.com/mchakravarty/CodeEditorView.git", branch: "main"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.13.0")
    ],
    targets: [
        .target(
            name: "AirCodeClient",
            dependencies: [
                .product(name: "CodeEditorView", package: "CodeEditorView"),
                .product(name: "LanguageSupport", package: "CodeEditorView"),
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ]
        ),
        .executableTarget(name: "AirCodePreview", dependencies: ["AirCodeClient"]),
        .executableTarget(name: "AirCodeIntegrationSmoke", dependencies: ["AirCodeClient"]),
        .testTarget(name: "AirCodeClientTests", dependencies: ["AirCodeClient"])
    ]
)
