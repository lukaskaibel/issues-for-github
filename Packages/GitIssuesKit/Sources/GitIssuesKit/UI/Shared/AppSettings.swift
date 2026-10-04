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
}

enum AppearanceSetting: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
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

/// The icons the app can wear in the Dock: four designs, each on a light and on a dark plate.
/// The first one is also the icon of the app bundle.
enum AppIconChoice: String, CaseIterable, Identifiable {
    /// The app's own icon, which follows the system's light or dark appearance.
    case card = "a"
    case cardLight = "a-light"
    case cardDark = "a-dark"
    case cardViolet = "a-violet"
    case boardLight = "e"
    case colourLight = "g"
    case barsLight = "i"
    case checklistLight = "j"
    case boardDark = "f"
    case colourDark = "g-dark"
    case barsDark = "i-dark"
    case checklistDark = "j-dark"

    static let cards: [AppIconChoice] = [.card, .cardLight, .cardDark, .cardViolet]
    static let light: [AppIconChoice] = [.boardLight, .colourLight, .barsLight, .checklistLight]
    static let dark: [AppIconChoice] = [.boardDark, .colourDark, .barsDark, .checklistDark]
    static let standard = AppIconChoice.card
    /// A new key with the card icon, so everyone starts from it once rather than keeping an older pick.
    static let defaultsKey = "dockIcon"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .card: "Card, light or dark with the system"
        case .cardLight: "Card, light"
        case .cardDark: "Card, dark"
        case .cardViolet: "Card on violet"
        case .boardLight: "Board"
        case .boardDark: "Board, dark"
        case .colourLight: "Board on colour"
        case .colourDark: "Board on colour, dark"
        case .barsLight: "Three bars"
        case .barsDark: "Three bars, dark"
        case .checklistLight: "Checklist"
        case .checklistDark: "Checklist, dark"
        }
    }

    private var resource: String {
        switch self {
        case .card: "icon-A-auto"
        case .cardLight: "icon-A-light"
        case .cardDark: "icon-A-dark"
        case .cardViolet: "icon-A-violet"
        case .boardLight: "icon-E"
        case .boardDark: "icon-F"
        case .colourLight: "icon-G"
        case .colourDark: "icon-G-dark"
        case .barsLight: "icon-I"
        case .barsDark: "icon-I-dark"
        case .checklistLight: "icon-J"
        case .checklistDark: "icon-J-dark"
        }
    }

    var image: PlatformImage? {
        #if os(macOS)
        Bundle.module.image(forResource: resource)
        #else
        UIImage(named: resource, in: .module, with: nil)
        #endif
    }

    @MainActor
    func apply() {
        #if os(macOS)
        // The standard icon is the bundle's own; setting nil hands the Dock back to it.
        NSApplication.shared.applicationIconImage = self == Self.standard ? nil : image
        #else
        // iOS shows an alert of its own whenever the icon changes, so only ask when it really differs.
        guard UIApplication.shared.supportsAlternateIcons,
              UIApplication.shared.alternateIconName != alternateIconName else { return }
        UIApplication.shared.setAlternateIconName(alternateIconName)
        #endif
    }

    /// The icons offered on iPhone and iPad: the card in its four looks.
    static let mobile: [AppIconChoice] = [.card, .cardLight, .cardDark, .cardViolet]

    /// Name of the alternate icon in the app bundle; nil is the app's own icon.
    var alternateIconName: String? {
        switch self {
        case .cardLight: "AppIcon-Light"
        case .cardDark: "AppIcon-Dark"
        case .cardViolet: "AppIcon-Violet"
        default: nil
        }
    }

    /// Short names for the iOS picker.
    var shortTitle: String {
        switch self {
        case .card: "Automatic"
        case .cardLight: "Light"
        case .cardDark: "Dark"
        case .cardViolet: "Violet"
        default: title
        }
    }

    #if os(iOS)
    /// The icon the system currently shows.
    @MainActor
    static var current: AppIconChoice {
        mobile.first { $0.alternateIconName == UIApplication.shared.alternateIconName } ?? .card
    }
    #endif
}

