import SwiftUI

// MARK: - Status

/// How a status is drawn: the circle that fills up as work progresses.
struct StatusGlyph: Equatable {
    var category: StatusCategory
    /// 0...1, how much of the circle is filled for in-progress statuses.
    var progress: Double
    var color: Color

    static let none = StatusGlyph(category: .backlog, progress: 0, color: Theme.textTertiary)

    /// Glyphs for all statuses of one project. Later "started" columns fill the circle further.
    static func map(for options: [FieldOption]) -> [String: StatusGlyph] {
        var result: [String: StatusGlyph] = [:]
        var startedIndex = 0
        for option in options {
            let category = option.statusCategory
            var progress = 0.0
            if category == .started {
                startedIndex += 1
                progress = 1 - pow(0.5, Double(startedIndex))
            }
            var color = Theme.statusColor(option)
            // Without a colour chosen on GitHub, tell consecutive in-progress columns apart.
            if category == .started, Theme.optionColor(option.color) == nil, startedIndex > 1 {
                color = Theme.positive
            }
            result[option.id] = StatusGlyph(category: category, progress: progress, color: color)
        }
        return result
    }
}

struct StatusIcon: View {
    var glyph: StatusGlyph
    var size: CGFloat = 14

    var body: some View {
        Canvas { context, canvasSize in
            StatusPainter.draw(glyph, in: CGRect(origin: .zero, size: canvasSize), context: context)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Priority

struct PriorityIcon: View {
    var level: PriorityLevel

    var body: some View {
        Group {
            if level == .urgent {
                ZStack {
                    RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Theme.urgent)
                    Text("!")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.onColor)
                }
                .frame(width: 12, height: 12)
            } else {
                HStack(alignment: .bottom, spacing: 2) {
                    bar(height: 4, on: level >= .low)
                    bar(height: 7, on: level >= .medium)
                    bar(height: 10, on: level >= .high)
                }
            }
        }
        .frame(width: 14, height: 12, alignment: .bottom)
        .accessibilityLabel(label)
    }

    private func bar(height: CGFloat, on: Bool) -> some View {
        RoundedRectangle(cornerRadius: 1).fill(on ? Theme.textBody : Theme.barOff).frame(width: 3, height: height)
    }

    private var label: String {
        switch level {
        case .none: "No priority"
        case .low: "Low priority"
        case .medium: "Medium priority"
        case .high: "High priority"
        case .urgent: "Urgent"
        }
    }
}

// MARK: - People and labels

/// Avatar images, downloaded once and kept decoded in memory so scrolling never waits for them.
final class AvatarCache: @unchecked Sendable {
    static let shared = AvatarCache()

    // NSCache is safe to read from any thread, which lets painted rows look images up while drawing.
    private let images = NSCache<NSString, PlatformImage>()
    @MainActor private var loading: [String: Task<PlatformImage?, Never>] = [:]

    func cached(_ url: String) -> PlatformImage? {
        images.object(forKey: url as NSString)
    }

    @MainActor
    func load(_ url: String) async -> PlatformImage? {
        if let image = cached(url) { return image }
        if let task = loading[url] { return await task.value }
        let task = Task<PlatformImage?, Never> {
            guard let parsed = URL(string: url + (url.contains("?") ? "&" : "?") + "s=72"),
                  let (data, _) = try? await URLSession.shared.data(from: parsed) else { return nil }
            return PlatformImage(data: data)
        }
        loading[url] = task
        let image = await task.value
        loading[url] = nil
        if let image { images.setObject(image, forKey: url as NSString) }
        return image
    }
}

struct Avatar: View {
    var login: String
    var url: String?
    var size: CGFloat = 18

    @State private var loaded: PlatformImage?

    var body: some View {
        let image = loaded ?? url.flatMap { AvatarCache.shared.cached($0) }
        ZStack {
            if let image {
                Image(platformImage: image)
                    .resizable()
                    .interpolation(.high)
                    .clipShape(Circle())
            } else {
                Circle().fill(color)
                Text(initials)
                    .font(.system(size: size * 0.44, weight: .bold))
                    .foregroundStyle(Color(hex: 0x111214))
            }
        }
        .frame(width: size, height: size)
        .help(login)
        .accessibilityLabel(login)
        .task(id: url) {
            guard let url, AvatarCache.shared.cached(url) == nil else { return }
            loaded = await AvatarCache.shared.load(url)
        }
    }

    private var initials: String {
        String(login.prefix(2)).uppercased()
    }

    private var color: Color { Self.color(for: login) }

    static func color(for login: String) -> Color {
        let hash = login.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return Theme.avatarPalette[hash % Theme.avatarPalette.count]
    }
}

struct AvatarStack: View {
    var people: [Person]
    var size: CGFloat = 18

    var body: some View {
        HStack(spacing: -5) {
            ForEach(people.prefix(3)) { person in
                Avatar(login: person.login, url: person.avatarUrl, size: size)
                    .overlay(Circle().stroke(Theme.card, lineWidth: 1.5))
            }
        }
    }
}

struct Chip<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 5) { content }
            .font(.tiny)
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .overlay(Capsule().stroke(Theme.chipBorder, lineWidth: 1))
    }
}

struct LabelChip: View {
    var label: LabelRef

    var body: some View {
        Chip {
            Circle().fill(Theme.labelColor(label.color)).frame(width: 7, height: 7)
            Text(label.name)
        }
    }
}

struct SubIssueChip: View {
    var completed: Int
    var total: Int

    var body: some View {
        Chip {
            SubIssueGlyph().frame(width: 11, height: 11)
            Text("\(completed)/\(total)").monospacedDigit()
        }
        .accessibilityLabel("\(completed) of \(total) sub-issues done")
    }
}

struct SubIssueGlyph: View {
    var body: some View {
        Canvas { context, size in
            let s = size.width / 12
            var path = Path()
            path.move(to: CGPoint(x: 2.5 * s, y: 2 * s))
            path.addLine(to: CGPoint(x: 2.5 * s, y: 6 * s))
            path.addQuadCurve(to: CGPoint(x: 4.5 * s, y: 8 * s), control: CGPoint(x: 2.5 * s, y: 8 * s))
            path.addLine(to: CGPoint(x: 6.6 * s, y: 8 * s))
            context.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: 1.3 * s, lineCap: .round))
            context.stroke(
                Path(ellipseIn: CGRect(x: 6.8 * s, y: 6.3 * s, width: 3.4 * s, height: 3.4 * s)),
                with: .foreground, lineWidth: 1.3 * s
            )
        }
    }
}

// MARK: - Small controls

struct Keycap: View {
    var text: String
    var emphasized = false

    init(_ text: String, emphasized: Bool = false) {
        self.text = text
        self.emphasized = emphasized
    }

    var body: some View {
        Text(text)
            .font(.tiny)
            .foregroundStyle(emphasized ? Theme.textBody : Theme.textSecondary)
            .padding(.horizontal, 5)
            .frame(minWidth: 20, minHeight: 20)
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Theme.keycapBorder, lineWidth: 1))
    }
}

struct ProjectSwatch: View {
    var title: String
    var size: CGFloat = 14

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private var color: Color {
        let hash = title.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return Theme.avatarPalette[hash % Theme.avatarPalette.count]
    }
}

/// Square icon button used in headers.
struct IconButton: View {
    var systemName: String
    var label: String
    var size: CGFloat = 24
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: size, height: size)
                .hoverFill(radius: 5)
        }
        .buttonStyle(PlainPressStyle())
        .help(label)
        .accessibilityLabel(label)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.accentFill))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.small)
            .foregroundStyle(Theme.textBody)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(configuration.isPressed ? Theme.controlActive : .clear))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Theme.keycapBorder, lineWidth: 1))
            .contentShape(Rectangle())
    }
}

func relativeDate(_ date: Date?) -> String {
    guard let date else { return "" }
    let calendar = Calendar.current
    if calendar.isDateInToday(date) {
        return date.formatted(date: .omitted, time: .shortened)
    }
    if calendar.component(.year, from: date) == calendar.component(.year, from: Date()) {
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
    return date.formatted(.dateTime.month(.abbreviated).year())
}

/// A thin bar for sub-issue progress.
struct ThinProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.cardBorder)
                Capsule().fill(Theme.accent)
                    .frame(width: proxy.size.width * (configuration.fractionCompleted ?? 0))
            }
        }
        .frame(height: 4)
        .animation(Theme.spring, value: configuration.fractionCompleted)
    }
}
