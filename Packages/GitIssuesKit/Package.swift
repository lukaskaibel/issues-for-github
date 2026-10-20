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
        // Exact: DiagramStore turns its Mac images the right way up, which a fix upstream would undo.
        .package(url: "https://github.com/lukilabs/beautiful-mermaid-swift", exact: "1.0.4"),
        // Typesets the $maths$ GitHub draws, as Notebook does.
        .package(url: "https://github.com/mgriebling/SwiftMath", from: "1.7.3"),
    ],
    targets: [
        .target(
            name: "GitIssuesKit",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "BeautifulMermaid", package: "beautiful-mermaid-swift"),
                .product(name: "SwiftMath", package: "SwiftMath"),
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
