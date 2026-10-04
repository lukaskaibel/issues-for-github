#if os(iOS)
import SwiftUI
import UIKit

/// The app's own glyphs as images for system menus, which only show images. Drawn for the current
/// appearance and kept, since menus are built every time they open.
@MainActor
enum MenuImages {
    private static var cache: [String: UIImage] = [:]

    static func status(_ glyph: StatusGlyph, _ scheme: ColorScheme) -> Image {
        image("status-\(glyph.category.rawValue)-\(glyph.progress)-\(key(glyph.color, scheme))", scheme) {
            StatusIcon(glyph: glyph, size: 16)
        }
    }

    static func priority(_ level: PriorityLevel, _ scheme: ColorScheme) -> Image {
        image("priority-\(level.rawValue)", scheme) {
            PriorityIcon(level: level)
        }
    }

    static func label(_ hex: String, _ scheme: ColorScheme) -> Image {
        image("label-\(hex)", scheme) {
            Circle().fill(Theme.labelColor(hex)).frame(width: 10, height: 10)
        }
    }

    static func avatar(_ person: Person, _ scheme: ColorScheme) -> Image {
        let picture = person.avatarUrl.flatMap { AvatarCache.shared.cached($0) }
        return image("avatar-\(person.login)-\(picture == nil ? "initials" : "picture")", scheme) {
            Avatar(login: person.login, url: person.avatarUrl, size: 20)
        }
    }

    /// A colour as a stable string, resolved for the appearance it is drawn in.
    private static func key(_ color: Color, _ scheme: ColorScheme) -> String {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        let resolved = color.resolve(in: environment)
        return String(format: "%.3f,%.3f,%.3f", resolved.red, resolved.green, resolved.blue)
    }

    private static func image<Content: View>(_ key: String, _ scheme: ColorScheme, @ViewBuilder content: () -> Content) -> Image {
        let fullKey = "\(key)-\(scheme == .dark ? "dark" : "light")"
        if let cached = cache[fullKey] { return Image(uiImage: cached) }
        let renderer = ImageRenderer(content: content()
            .frame(width: 22, height: 22)
            .environment(\.colorScheme, scheme))
        renderer.scale = 3
        guard let rendered = renderer.uiImage?.withRenderingMode(.alwaysOriginal) else {
            return Image(systemName: "circle")
        }
        cache[fullKey] = rendered
        return Image(uiImage: rendered)
    }
}
#endif
