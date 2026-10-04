// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GitIssuesKit",
    platforms: [.macOS("27.0"), .iOS("27.0")],
    products: [
        .library(name: "GitIssuesKit", targets: ["GitIssuesKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui.git", from: "2.4.0"),
    ],
    targets: [
        .target(
            name: "GitIssuesKit",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
            ],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "gi-cli",
            dependencies: ["GitIssuesKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "GitIssuesKitTests",
            dependencies: ["GitIssuesKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
