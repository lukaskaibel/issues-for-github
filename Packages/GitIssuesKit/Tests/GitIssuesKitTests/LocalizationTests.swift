import Foundation
import Testing
@testable import GitIssuesKit

/// The String Catalog: every text translated into every language, placeholders a translation can't get wrong, and
/// no English left in the code where no translation reaches it. `Tools/strings.py check` runs the same checks
/// without building.
@Suite("Translations")
struct LocalizationTests {
    static let languages = ["de", "es", "fr", "ja", "ko", "pt-BR", "ru", "zh-Hans"]
    /// The plural forms each language needs. Spanish, French and Portuguese also know "many" (a million), which
    /// falls back to "other".
    static let plurals: [String: Set<String>] = [
        "en": ["one", "other"], "de": ["one", "other"], "es": ["one", "other"], "fr": ["one", "other"],
        "ja": ["other"], "ko": ["other"], "pt-BR": ["one", "other"], "ru": ["one", "few", "many", "other"],
        "zh-Hans": ["other"],
    ]

    static let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Sources/GitIssuesKit")

    static let catalog: [String: Entry] = {
        let url = sources.appending(path: "Resources/Localizable.xcstrings")
        let file = try! JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
        return file.strings
    }()

    static let code: [(file: String, text: String)] = {
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
        return files.map { ($0.lastPathComponent, try! String(contentsOf: $0, encoding: .utf8)) }
    }()

    // MARK: The catalog

    @Test func everyTextIsASymbolWithAComment() {
        for (key, entry) in Self.catalog {
            #expect(key.wholeMatch(of: #/[a-z][A-Za-z0-9]*/#) != nil, "\(key): keys are camelCase Swift names")
            #expect(entry.extractionState == "manual", "\(key): only manual strings get a symbol")
            #expect(!(entry.comment ?? "").isEmpty, "\(key): say where it appears, for whoever translates it")
            #expect(entry.localizations["en"] != nil, "\(key): no English")
        }
    }

    @Test(arguments: languages)
    func everyTextIsTranslated(into language: String) {
        for (key, entry) in Self.catalog {
            guard let localization = entry.localizations[language] else {
                Issue.record("\(key) has no \(language)")
                continue
            }
            let units = localization.units()
            #expect(!units.isEmpty, "\(key) (\(language)) is empty")
            for (path, unit) in units {
                #expect(unit.state == "translated", "\(key) (\(language)) \(path) is \(unit.state)")
                #expect(!unit.value.trimmingCharacters(in: .whitespaces).isEmpty, "\(key) (\(language)) \(path) is blank")
            }
            if let plural = localization.variations?["plural"] {
                let missing = Self.plurals[language]!.subtracting(plural.keys)
                #expect(missing.isEmpty, "\(key) (\(language)) lacks the plural forms \(missing.sorted())")
            }
        }
    }

    /// A translation must pass its arguments the same way as the English, or the app crashes on it.
    @Test(arguments: languages)
    func placeholdersMatchTheEnglish(in language: String) throws {
        for (key, entry) in Self.catalog {
            guard let english = entry.localizations["en"], let localization = entry.localizations[language] else { continue }
            let source = try english.signature()
            let translated = try localization.signature()
            for (position, kind) in translated {
                #expect(source[position] == kind, "\(key) (\(language)): argument \(position) is \(kind), English has \(source[position] ?? "none")")
            }
            for (path, unit) in localization.units() where !path.hasPrefix("%#@") {
                #expect(!unit.value.contains("%("), "\(key) (\(language)): named placeholders only in English")
                if source.count > 1 {
                    for match in unit.value.matches(of: Placeholder.pattern) where match.output.conversion != nil {
                        #expect(match.output.position != nil, "\(key) (\(language)): number the placeholders, as there are several")
                    }
                }
            }
        }
    }

    /// Formats every text in every language from the compiled tables, as the app does.
    @Test(arguments: ["en"] + languages)
    func everyTextFormats(in language: String) throws {
        let path = try #require(Bundle.module.path(forResource: language, ofType: "lproj"), "no \(language).lproj")
        let bundle = try #require(Bundle(path: path))
        for (key, entry) in Self.catalog {
            let format = bundle.localizedString(forKey: key, value: "\u{0}", table: "Localizable")
            #expect(format != "\u{0}" && format != key, "\(key) is missing from \(language).lproj")
            guard let english = entry.localizations["en"] else { continue }
            let signature = try english.signature()
            for count in [1, 2, 5, 21] {
                let arguments: [CVarArg] = (0..<(signature.keys.max() ?? 0)).map {
                    switch signature[$0 + 1] {
                    case "double": Double(count)
                    case "object": "Name" as NSString
                    default: count
                    }
                }
                let text = String(format: format, locale: Locale(identifier: language), arguments: arguments)
                #expect(!text.contains("%"), "\(key) (\(language)) left a placeholder: \(text)")
            }
        }
    }

    // MARK: The code

    @Test func everyTextIsUsed() {
        let members = Set(Self.code.flatMap { $0.text.matches(of: #/\.([a-z][A-Za-z0-9]*)/#).map { String($0.output.1) } })
        for key in Self.catalog.keys {
            #expect(members.contains(key), "\(key) isn't used")
        }
    }

    /// English written straight into a view is never translated. GitHub's own words (field names, enum values)
    /// and the debugging tools stay as they are.
    @Test func noEnglishLeftInTheCode() {
        let skipped: Set<String> = ["DebugRemote.swift", "DemoData.swift"]
        for (file, text) in Self.code where !skipped.contains(file) {
            for (number, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let code = line.split(separator: "//", maxSplits: 1).first.map(String.init) ?? ""
                let literals = code.matches(of: Self.textInView).map { String($0.output.1) }
                    + code.matches(of: Self.textToHelper).map { String($0.output.1) }
                for literal in literals {
                    if Self.notForTranslation.contains(literal) || Self.notForTranslation.contains("\(file): \(literal)")
                        || literal.contains(Self.sqlOrHeader) { continue }
                    Issue.record("\(file):\(number + 1): \"\(literal)\" is English in the code; add it to the catalog")
                }
            }
        }
    }

    /// A string literal handed to a view or to a parameter that shows it, which reads like words.
    static let textInView = #/(?:\b(?:Text|Button|Label|Toggle|Section|Menu|Picker|TextField|SecureField|LabeledContent|ContentUnavailableView|NavigationLink|Tab|CommandMenu|CommandGroup|Link|ShareLink|GroupBox|DisclosureGroup|ProgressView|ClosureMenuItem|NSMenuItem)\(|\.(?:navigationTitle|help|accessibilityLabel|accessibilityHint|accessibilityValue|alert|confirmationDialog|badge|screenKey)\(|\b(?:title|label|text|message|placeholder|subtitle|prompt|tooltip|hint|lead|detail|named|header|footer|caption|body):\s*|\breturn\s+|\?\s*|:\s+(?=")|\?\?\s*)"((?:[A-Z][a-z’']|(?:[^"\\]|\\.)*[A-Za-z] [A-Za-z])(?:[^"\\]|\\.)*)"/#

    /// A capitalised text as the first argument of a function of the app's own, as in `submenu("Mark As", …)`.
    static let textToHelper = #/\b(?!print\b|fatalError\b|assert\b|precondition\b|assertionFailure\b)[a-z][A-Za-z]*\(\s*"([A-Z][a-z’']+(?:[ …][^"]*)?)"/#

    /// SQL, and HTTP header names such as "Content-Type".
    static let sqlOrHeader = #/^(?:SELECT|UPDATE|INSERT|DELETE|CREATE|ALTER|DROP|PRAGMA|WITH) |^[A-Z][a-z]+(?:-[A-Z][a-z]+)+$/#

    /// English that isn't shown as UI text.
    static let notForTranslation: Set<String> = [
        // The brand, shown in place of the login until it is known.
        "GitHub",
        // Field and option names the app looks for or creates on GitHub, where teammates see them.
        "Status", "Priority", "Due date", "Urgent", "High", "Medium", "Low",
        // GitHub's search query, HTTP headers and the Info.plist key of the OAuth app.
        "is:issue is:open assignee:@me archived:false", "Authorization", "Accept", "Link", "GitHubClientID",
        // Names inside the app: the database folder, alternate icons, a date template, a background task.
        "GitIssues", "AppIcon-Light", "AppIcon-Dark", "AppIcon-Violet", "Md", "Send queued changes",
        // GitHub's names for what a notification is about.
        "Inbox.swift: Issue", "PullRequest",
        // For whoever debugs: a database that can't be migrated, and errors the debug build can simulate.
        "The item table has an unexpected definition: \\(definition)", "Simulated for testing.", "The network connection was lost.",
    ]
}

// MARK: - Reading the catalog

struct Catalog: Decodable {
    var strings: [String: LocalizationTests.Entry]
}

extension LocalizationTests {
    struct Entry: Decodable {
        var comment: String?
        var extractionState: String?
        var localizations: [String: Localization] = [:]

        enum CodingKeys: CodingKey { case comment, extractionState, localizations }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            comment = try container.decodeIfPresent(String.self, forKey: .comment)
            extractionState = try container.decodeIfPresent(String.self, forKey: .extractionState)
            localizations = try container.decodeIfPresent([String: Localization].self, forKey: .localizations) ?? [:]
        }
    }

    struct StringUnit: Decodable {
        var state: String
        var value: String
    }

    final class Localization: Decodable {
        var stringUnit: StringUnit?
        var variations: [String: [String: Localization]]?
        var substitutions: [String: Substitution]?

        /// Every text in it, with a path like "plural.one/" for each variation.
        func units(_ path: String = "") -> [(String, StringUnit)] {
            var result: [(String, StringUnit)] = []
            if let stringUnit { result.append((path, stringUnit)) }
            for (name, cases) in variations ?? [:] {
                for (form, child) in cases { result += child.units("\(path)\(name).\(form)/") }
            }
            for (name, substitution) in substitutions ?? [:] {
                for (form, child) in substitution.variations?["plural"] ?? [:] {
                    result += child.units("%#@\(name)@/plural.\(form)/")
                }
            }
            return result
        }

        /// Position → "int", "double" or "object", over every variation.
        func signature() throws -> [Int: String] {
            var positions: [Int: String] = [:]
            for (path, unit) in units() where !path.hasPrefix("%#@") {
                var names: [String: Int] = [:]
                var sequential = 0
                for match in unit.value.matches(of: Placeholder.pattern) {
                    let position: Int
                    let kind: String
                    if let substitution = match.output.substitution {
                        guard let found = substitutions?[String(substitution)] else {
                            throw CatalogError.missingSubstitution(String(substitution))
                        }
                        position = found.argNum
                        kind = Placeholder.kind(of: found.formatSpecifier)
                    } else if let conversion = match.output.conversion {
                        if let explicit = match.output.position {
                            position = Int(explicit)!
                        } else if let name = match.output.name {
                            position = names[String(name)] ?? (names.count + 1)
                            names[String(name)] = position
                        } else {
                            sequential += 1
                            position = sequential
                        }
                        kind = Placeholder.kind(of: String(conversion))
                    } else {
                        continue
                    }
                    if let earlier = positions[position], earlier != kind {
                        Issue.record("argument \(position) is used as \(earlier) and \(kind)")
                    }
                    positions[position] = kind
                }
            }
            return positions
        }
    }

    enum CatalogError: Error {
        case missingSubstitution(String)
    }

    struct Substitution: Decodable {
        var argNum: Int
        var formatSpecifier: String
        var variations: [String: [String: Localization]]?
    }

    enum Placeholder {
        static let pattern = #/%%|%#@(?<substitution>\w+)@|%(?:(?<position>\d+)\$|\((?<name>\w+)\))?[-+ 0#']*\d*(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j)?(?<conversion>[@dDiuUxXoOfFeEgGaAcCsSp])/#

        static func kind(of specifier: String) -> String {
            switch specifier.last {
            case "@": "object"
            case "f", "F", "e", "E", "g", "G", "a", "A": "double"
            default: "int"
            }
        }
    }
}
