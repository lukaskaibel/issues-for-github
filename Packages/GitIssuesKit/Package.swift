// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GitIssuesKit",
    // The texts are written in English and translated in Sources/GitIssuesKit/Resources/Localizable.xcstrings.
    defaultLocalization: "en",
    platforms: [.macOS("27.0"), .iOS("27.0")],
    products: [
        .library(name: "GitIssuesKit", targets: ["GitIssuesKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui.git", from: "2.4.0"),
        // The parser MarkdownUI reads with, to find checkboxes and tables in a description the same way.
        .package(url: "https://github.com/swiftlang/swift-cmark", from: "0.4.0"),
        // Exact: MermaidDiagram turns its Mac images the right way up, which a fix upstream would undo.
        .package(url: "https://github.com/lukilabs/beautiful-mermaid-swift", exact: "1.0.4"),
    ],
    targets: [
        .target(
            name: "GitIssuesKit",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
                .product(name: "BeautifulMermaid", package: "beautiful-mermaid-swift"),
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
            dependencies: [
                "GitIssuesKit",
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
