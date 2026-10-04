import SwiftUI
#if os(macOS)
import AppKit

typealias PlatformColor = NSColor
typealias PlatformImage = NSImage
typealias PlatformFont = NSFont
#else
import UIKit

typealias PlatformColor = UIColor
typealias PlatformImage = UIImage
typealias PlatformFont = UIFont
#endif

/// The few things AppKit and UIKit spell differently, so shared views can stay free of `#if`.
enum Platform {
    /// Opens a link in the default browser (or the app that handles it).
    @MainActor
    static func open(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }

    @MainActor
    static func copy(_ string: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #else
        UIPasteboard.general.string = string
        #endif
    }
}

extension PlatformColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    #if os(iOS)
    convenience init(srgbRed red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
    #endif

    /// A colour that is worked out again whenever the appearance changes.
    static func dynamic(_ provider: @escaping @Sendable (_ isDark: Bool) -> PlatformColor) -> PlatformColor {
        #if os(macOS)
        NSColor(name: nil) { appearance in
            provider(appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        }
        #else
        UIColor { traits in provider(traits.userInterfaceStyle == .dark) }
        #endif
    }
}

extension Color {
    init(platformColor: PlatformColor) {
        #if os(macOS)
        self.init(nsColor: platformColor)
        #else
        self.init(uiColor: platformColor)
        #endif
    }
}

extension Image {
    init(platformImage: PlatformImage) {
        #if os(macOS)
        self.init(nsImage: platformImage)
        #else
        self.init(uiImage: platformImage)
        #endif
    }
}

extension PlatformFont {
    /// The font with italics added, keeping its size and weight.
    func italicized() -> PlatformFont {
        #if os(macOS)
        NSFontManager.shared.convert(self, toHaveTrait: .italicFontMask)
        #else
        fontDescriptor.withSymbolicTraits(fontDescriptor.symbolicTraits.union(.traitItalic))
            .map { UIFont(descriptor: $0, size: pointSize) } ?? self
        #endif
    }
}
