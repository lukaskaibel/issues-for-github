import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// One place in the app: which project or view, shown as board or list, and which issue is open.
struct Location: Equatable {
    var scope: Scope?
    var viewMode: ViewMode
    var itemId: String?
    /// The view open in the project, when the place is a project's.
    var viewId: String? = nil
}

enum AppearanceSetting: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: String(localized: .appearanceSystem)
        case .light: String(localized: .appearanceLight)
        case .dark: String(localized: .appearanceDark)
        }
    }

    var systemImage: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    @MainActor
    func apply() {
        #if os(macOS)
        switch self {
        case .system: NSApplication.shared.appearance = nil
        case .light: NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case .dark: NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        }
        #else
        // Every window, so sheets and a second iPad window follow too.
        let style: UIUserInterfaceStyle = switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows { window.overrideUserInterfaceStyle = style }
        }
        #endif
    }
}

/// The icons the app can wear: a card lifted off a board, on its light page, on graphite or on indigo, each with a
/// light and a dark look that follows the system. The card on its page is the app bundle's own icon.
enum AppIconChoice: String, CaseIterable, Identifiable {
    case card
    case graphite
    case indigo

    static let standard = AppIconChoice.card
    /// Picks stored under earlier designs (the board, the pinboard's materials, "a", "e" and so on) no longer read, so
    /// everyone else starts from the card.
    static let defaultsKey = "dockIcon"

    var id: String { rawValue }

    var title: String {
        let name: LocalizedStringResource = switch self {
        case .card: .appIconCard
        case .graphite: .appIconGraphite
        case .indigo: .appIconIndigo
        }
        return String(localized: name)
    }

    /// The icon as the Dock or Home Screen shows it, in the light or the dark look.
    func image(dark: Bool) -> PlatformImage? {
        let resource = "icon-\(rawValue)-\(dark ? "dark" : "light")"
        #if os(macOS)
        return Bundle.module.image(forResource: resource)
        #else
        return UIImage(named: resource, in: .module, with: nil)
        #endif
    }

    @MainActor
    func apply() {
        #if os(macOS)
        // The standard icon is the bundle's own and follows light and dark by itself; nil hands the Dock back to it.
        // The others are pictures, so they are set again whenever the system's appearance changes.
        NSApplication.shared.applicationIconImage = self == Self.standard ? nil : image(dark: Self.systemIsDark)
        #else
        // iOS shows an alert of its own whenever the icon changes, so only ask when it really differs.
        guard UIApplication.shared.supportsAlternateIcons,
              UIApplication.shared.alternateIconName != alternateIconName else { return }
        UIApplication.shared.setAlternateIconName(alternateIconName)
        #endif
    }

    #if os(macOS)
    /// The system's appearance rather than the app's: the Dock follows the system, even when the app is set to light or dark.
    static var systemIsDark: Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }
    #endif

    /// Name of the alternate icon in the app bundle; nil is the app's own icon.
    var alternateIconName: String? {
        switch self {
        case .card: nil
        case .graphite: "AppIcon-Graphite"
        case .indigo: "AppIcon-Indigo"
        }
    }

    #if os(iOS)
    /// The icon the system currently shows.
    @MainActor
    static var current: AppIconChoice {
        allCases.first { $0.alternateIconName == UIApplication.shared.alternateIconName } ?? .standard
    }
    #endif
}
