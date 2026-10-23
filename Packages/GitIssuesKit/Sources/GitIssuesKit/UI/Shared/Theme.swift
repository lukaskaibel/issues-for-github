import SwiftUI

/// Design tokens. Every colour in the app comes from here and has a light and a dark value.
enum Theme {
    // Apple's own greys, as in Notes, Mail and Reminders: white pages, a neutral grey dark appearance.
    static let window = Color(light: 0xF3F3F5, dark: 0x1A1A1C)
    static let panel = Color(light: 0xFFFFFF, dark: 0x1E1E20)
    static let panelBorder = Color(light: 0xE5E5EA, dark: 0x2E2E31)
    static let groupHeader = Color(light: 0xF4F4F6, dark: 0x252527)
    static let rowSeparator = Color(light: 0xEDEDF0, dark: 0x2A2A2D)
    /// A soft grey block on a white page, such as an activity in the Inbox.
    static let lane = Color(light: 0xF4F4F6, dark: 0x242427)
    /// Behind the whole board, as Apple's grouped lists stand on grey: its white cards need no border on it, and its
    /// columns no lanes.
    static let board = Color(light: 0xF3F3F5, dark: 0x19191B)

    static let card = Color(light: 0xFFFFFF, dark: 0x2C2C2F)
    static let cardBorder = Color(light: 0xE4E4E9, dark: 0x37373B)
    static let cardHover = Color(light: 0xFCFCFD, dark: 0x343438)
    static let cardHoverBorder = Color(light: 0xD1D1D6, dark: 0x48484D)
    static let cardLifted = Color(light: 0xFFFFFF, dark: 0x343438)
    static let cardLiftedBorder = Color(light: 0xC7C7CC, dark: 0x4A4A4F)
    /// The soft shadow a board card stands on, in place of a border.
    static let cardShadow = Color(platformColor: .dynamic { isDark in
        PlatformColor.black.withAlphaComponent(isDark ? 0.4 : 0.07)
    })
    /// The deeper shadow of a card under the pointer or the keyboard, which seems to rise towards it.
    static let cardRaisedShadow = Color(platformColor: .dynamic { isDark in
        PlatformColor.black.withAlphaComponent(isDark ? 0.5 : 0.11)
    })
    /// The edge of a second card peeking out under one whose sub-issues are folded into it: a shade darker, as the
    /// notifications behind the first one in a stack are.
    static let cardBehind = Color(light: 0xE4E4E9, dark: 0x242427)

    static let hover = Color(light: 0xEDEDF0, dark: 0x2C2C2F)
    static let selected = Color(light: 0xEBEBEF, dark: 0x2F2F33)
    static let control = Color(light: 0xE9E9ED, dark: 0x2C2C2F)
    static let controlActive = Color(light: 0xE1E1E6, dark: 0x3A3A3E)
    static let chipBorder = Color(light: 0xDCDCE1, dark: 0x3A3A3E)
    /// A chip under the pointer lights up in its own shape rather than getting a box behind it.
    static let chipHover = Color(light: 0xEFEFF3, dark: 0x343438)
    static let chipHoverBorder = Color(light: 0xC7C7CC, dark: 0x4A4A4F)
    /// A picked issue: a tint of the accent behind it and the accent around it.
    static let selectionFill = Color(light: 0xEDEEFC, dark: 0x2A2C47)
    static let selectionBorder = Color(light: 0x8D93E6, dark: 0x6E75D8)
    /// Behind a small icon or avatar under the pointer.
    static let partHover = Color(light: 0xE5E5EA, dark: 0x3A3A3E)

    static let popover = Color(light: 0xFFFFFF, dark: 0x2A2A2D)
    static let popoverBorder = Color(light: 0xDEDEE3, dark: 0x3A3A3E)
    static let popoverSelected = Color(light: 0xEEEEF2, dark: 0x3A3A3E)
    /// The row under the pointer or the arrow keys in a dropdown: a soft tint of the accent, which keeps the
    /// indigo Done circle visible where a full accent fill would swallow it.
    static let menuHighlight = Color(platformColor: .dynamic { isDark in
        PlatformColor(hex: isDark ? 0x8F96F2 : 0x5B63D3).withAlphaComponent(isDark ? 0.24 : 0.14)
    })
    /// The search field at the top of a dropdown and other fields drawn on glass.
    static let field = Color(platformColor: .dynamic { isDark in
        isDark ? PlatformColor.white.withAlphaComponent(0.08) : PlatformColor.black.withAlphaComponent(0.05)
    })
    static let keycapBorder = Color(light: 0xD1D1D6, dark: 0x48484D)

    static let text = Color(light: 0x1D1D1F, dark: 0xF2F2F4)
    static let textSecondary = Color(light: 0x5E5E63, dark: 0xAEAEB4)
    static let textTertiary = Color(light: 0x6E6E73, dark: 0x8E8E95)
    static let textBody = Color(light: 0x2C2C2E, dark: 0xD8D8DC)

    static let accent = Color(light: 0x5B63D3, dark: 0x8F96F2)
    static let accentFill = Color(light: 0x5B63D3, dark: 0x5B63D3)
    static let positive = Color(light: 0x2F9B67, dark: 0x4CB782)
    static let warning = Color(light: 0xB8791C, dark: 0xE5A84B)
    static let urgent = Color(light: 0xE07B2A, dark: 0xF2994A)
    /// A due date that has passed.
    static let overdue = Color(light: 0xD64545, dark: 0xEB6A6A)
    /// An issue that waits for another one, as Linear marks it.
    static let blocked = Color(light: 0xD9473B, dark: 0xEB5B50)
    static let barOff = Color(light: 0xD1D1D6, dark: 0x48484D)
    /// The line from a parent down to the sub-issues hanging under it.
    static let treeLine = Color(light: 0xD1D1D6, dark: 0x3F3F43)
    /// The active half of a segmented control.
    static let segmentActive = Color(light: 0xFFFFFF, dark: 0x3A3A3E)
    /// Text set on top of a filled, coloured shape (avatars, the urgent badge, the done check mark).
    static let onColor = Color(light: 0xFFFFFF, dark: 0x1C1C1E)
    static let started = Color(light: 0xD29A0A, dark: 0xF0B429)
    /// Epics, which group issues on the roadmap: their icon and their bars.
    static let epic = Color(light: 0x6E56CF, dark: 0xA08CF2)
    static let epicBar = Color(light: 0xECE8FA, dark: 0x2B2640)
    static let epicBarBorder = Color(light: 0xB9AEE9, dark: 0x4C4380)
    static let epicBarFill = Color(light: 0xB7A9EC, dark: 0x5C4FA0)
    /// A milestone's stretch of time on the roadmap, every other one.
    static let timelineBand = Color(light: 0xF5F5F7, dark: 0x232326)
    static let scrim = Color(light: 0x1C1C1E, dark: 0x000000).opacity(0.25)
    static let shadow = Color(platformColor: .dynamic { isDark in
        PlatformColor.black.withAlphaComponent(isDark ? 0.5 : 0.16)
    })

    static let spring = Animation.spring(response: 0.3, dampingFraction: 0.82)
    static let quick = Animation.easeOut(duration: 0.14)
    static let overlay = Animation.spring(response: 0.26, dampingFraction: 0.86)
    /// How long Markdown takes to change its look as you type: bold thickening, a heading growing, marks fading.
    static let textStyleDuration: TimeInterval = 0.18
    /// Markdown marks unfolding next to the caret and folding away behind it.
    static let markRevealDuration: TimeInterval = 0.16
    /// The buttons for where the caret is, coming and going in the bar above the keyboard (UIKit spring).
    static let keyboardBarSpring: (duration: TimeInterval, bounce: CGFloat) = (0.32, 0.16)

    static let sidebarWidth: CGFloat = 220
    /// The Inbox's list beside the issue, as wide as Linear's.
    static let inboxListWidth: CGFloat = 372
    static let headerHeight: CGFloat = 44
    static let rowHeight: CGFloat = 36

    /// GitHub's eight option colours, tuned for each ground.
    static func optionColor(_ name: String) -> Color? {
        switch name {
        case "BLUE": Color(light: 0x2F86B5, dark: 0x5AB0D8)
        case "GREEN": Color(light: 0x2F9B67, dark: 0x4CB782)
        case "YELLOW": Color(light: 0xD29A0A, dark: 0xF0B429)
        case "ORANGE": Color(light: 0xE07B2A, dark: 0xF2994A)
        case "RED": Color(light: 0xD64545, dark: 0xEB6A6A)
        case "PINK": Color(light: 0xC45FA6, dark: 0xD98BC4)
        case "PURPLE": Color(light: 0x5B63D3, dark: 0x8F96F2)
        default: nil
        }
    }

    /// A project's glyph in one of GitHub's option colours; grey is the grey of secondary text, like other icons.
    static func projectColor(_ name: String) -> Color {
        optionColor(name) ?? textSecondary
    }

    static func statusColor(_ option: FieldOption?) -> Color {
        guard let option else { return textTertiary }
        if let color = optionColor(option.color) { return color }
        switch option.statusCategory {
        case .backlog, .canceled: return textTertiary
        case .unstarted: return textBody
        case .started: return started
        case .completed: return accent
        }
    }

    /// Label colours come from GitHub as hex. Very dark ones are lifted on the dark ground and very
    /// light ones deepened on the light ground, so a label never disappears.
    static func labelColor(_ hex: String) -> Color {
        guard let value = UInt32(hex, radix: 16) else { return textSecondary }
        let r = Double((value >> 16) & 0xFF) / 255, g = Double((value >> 8) & 0xFF) / 255, b = Double(value & 0xFF) / 255
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return Color(platformColor: .dynamic { isDark in
            if isDark, luminance < 0.25 {
                let lift = 0.45
                return PlatformColor(srgbRed: r + (1 - r) * lift, green: g + (1 - g) * lift, blue: b + (1 - b) * lift, alpha: 1)
            }
            if !isDark, luminance > 0.7 {
                let keep = 0.62
                return PlatformColor(srgbRed: r * keep, green: g * keep, blue: b * keep, alpha: 1)
            }
            return PlatformColor(srgbRed: r, green: g, blue: b, alpha: 1)
        })
    }

    static let avatarPalette: [Color] = [
        Color(hex: 0x8F96F2), Color(hex: 0x4CB782), Color(hex: 0xE5A84B),
        Color(hex: 0x5AB0D8), Color(hex: 0xD98BC4), Color(hex: 0xC792EA),
    ]
}

extension Color {
    /// A colour that follows the window's appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(platformColor: .dynamic { isDark in PlatformColor(hex: isDark ? dark : light) })
    }

    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension Font {
    #if os(macOS)
    static let ui = Font.system(size: 13)
    static let uiMedium = Font.system(size: 13, weight: .medium)
    static let uiSemibold = Font.system(size: 13, weight: .semibold)
    static let small = Font.system(size: 12)
    static let smallMedium = Font.system(size: 12, weight: .medium)
    static let tiny = Font.system(size: 11)
    static let tinySemibold = Font.system(size: 11, weight: .semibold)
    /// A heading inside a page, such as Sub-issues or Activity.
    static let sectionTitle = Font.system(size: 16, weight: .bold)
    #else
    // On iPhone and iPad the same roles follow the reader's text size.
    static let ui = Font.callout
    static let uiMedium = Font.callout.weight(.medium)
    static let uiSemibold = Font.callout.weight(.semibold)
    static let small = Font.footnote
    static let smallMedium = Font.footnote.weight(.medium)
    static let tiny = Font.caption
    static let tinySemibold = Font.caption.weight(.semibold)
    static let sectionTitle = Font.title3.weight(.bold)
    #endif
}

extension View {
    /// Liquid Glass, as the system draws what floats over the content: bars, panels, the comment field. Debug runs
    /// can ask for a solid ground instead (`-debugSolidGlass YES`), since the app's own snapshots can't draw glass.
    @ViewBuilder
    func glassPanel<S: Shape>(in shape: S) -> some View {
        if Theme.solidGlass {
            background(shape.fill(Theme.popover)).overlay(shape.stroke(Theme.popoverBorder, lineWidth: 0.5))
        } else {
            glassEffect(.regular, in: shape)
        }
    }

    /// A bar at the foot of a scrolling page, such as the comment field. The page scrolls up clear of it and, just
    /// above it, blurs and fades into its ground, as under the toolbar: nothing shows through the bar's glass or in
    /// the strip beneath it.
    func pageFootBar(@ViewBuilder _ bar: () -> some View) -> some View {
        // The system's soft edge alone leaves text legible under the bar (faint on the Mac, blurred on iPhone), so
        // the page's own ground rises behind the bar too.
        scrollEdgeEffectStyle(.soft, for: .bottom)
            .safeAreaBar(edge: .bottom, spacing: 0) {
                bar().background(alignment: .top) {
                    VStack(spacing: 0) {
                        LinearGradient(colors: [Theme.panel.opacity(0), Theme.panel], startPoint: .top, endPoint: .bottom)
                            .frame(height: Theme.pageEdgeFade)
                        Theme.panel
                    }
                    .padding(.top, -Theme.pageEdgeFade)
                    .ignoresSafeArea(edges: .bottom)
                    .allowsHitTesting(false)
                }
            }
    }
}

#if os(macOS)
extension View {
    /// A scrolling page under the window's toolbar. The page's ground lies behind the toolbar, and what scrolls up
    /// fades into it just below, as above the comment field: nothing runs through the title or past the toolbar's
    /// buttons.
    func pageUnderToolbar() -> some View {
        modifier(PageUnderToolbar())
    }
}

private struct PageUnderToolbar: ViewModifier {
    /// How far the page has scrolled under the toolbar, up to the length of the fade. The fade comes in with it, so a
    /// page at its top shows its first line in full.
    @State private var scrolled: CGFloat = 0

    func body(content: Content) -> some View {
        // The toolbar's own background, the system's edge effect, differs from page to page: on the issue page the
        // text stays sharp under the title, over the Inbox lies a film of another grey with a line under it. So the
        // page's ground takes its place, as at the foot.
        content
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                min(max(geometry.contentOffset.y + geometry.contentInsets.top, 0), Theme.pageEdgeFade)
            } action: { _, offset in
                scrolled = offset
            }
            .safeAreaBar(edge: .top, spacing: 0) {
                Color.clear.frame(height: 0).background(alignment: .bottom) {
                    VStack(spacing: 0) {
                        Theme.panel
                        LinearGradient(colors: [Theme.panel, Theme.panel.opacity(0)], startPoint: .top, endPoint: .bottom)
                            .frame(height: Theme.pageEdgeFade)
                            .opacity(scrolled / Theme.pageEdgeFade)
                    }
                    .padding(.bottom, -Theme.pageEdgeFade)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
                }
            }
    }
}
#endif

extension Theme {
    /// How far from the toolbar above a page, or from a bar at its foot, the page fades out.
    static let pageEdgeFade: CGFloat = 24

    static var solidGlass: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "debugSolidGlass")
        #else
        false
        #endif
    }
}

/// A button that looks like plain content and dims slightly while pressed.
struct PlainPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
    }
}

/// Background that lights up on hover, used for sidebar rows, toolbar buttons and menu rows.
struct HoverFill: ViewModifier {
    var active = false
    var radius: CGFloat = 6
    var fill = Theme.hover
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(active || hovering ? fill : .clear)
            )
            .onHover { hovering = $0 }
            .animation(Theme.quick, value: hovering)
    }
}

extension View {
    func hoverFill(active: Bool = false, radius: CGFloat = 6, fill: Color = Theme.hover) -> some View {
        modifier(HoverFill(active: active, radius: radius, fill: fill))
    }
}
