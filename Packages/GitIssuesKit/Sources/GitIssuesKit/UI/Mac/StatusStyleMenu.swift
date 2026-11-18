#if os(macOS)
import SwiftUI

/// A small button on the lit status row of a picker: opens the status's icon and colour over the picker, which stays
/// open beneath, so a status can be adjusted right where it is picked.
struct StatusStyleButton: View {
    var option: FieldOption
    /// On the row under the pointer or the keys; hidden on the others, so the list stays calm.
    var shown: Bool

    @State private var open = false
    @State private var hovering = false

    var body: some View {
        Button {
            open = true
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 22, height: 20)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(hovering || open ? Theme.partHover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainPressStyle())
        .onHover { hovering = $0 }
        .opacity(shown || open ? 1 : 0)
        .allowsHitTesting(shown || open)
        .help(Text(.statusIconAndColourTooltip))
        .accessibilityLabel(Text(.statusIconAndColourTooltip))
        .dropdown(isPresented: $open) { close in
            StatusStyleMenu(option: option, close: close)
        }
    }
}

/// A status's icon, which says what it means, and its colour on GitHub. An icon closes the menu; a colour keeps it open
/// for an icon to follow, as a project's icon does.
struct StatusStyleMenu: View {
    @Environment(AppModel.self) private var model
    var option: FieldOption
    var close: () -> Void

    @State private var lit: StatusCategory?

    var body: some View {
        // The status as it is now: a colour just picked shows in the icons at once.
        let current = model.statusOptions(projectId: option.projectId).first { $0.id == option.id } ?? option
        VStack(alignment: .leading, spacing: 0) {
            heading(.statusIcon)
            ForEach(AppModel.statusKindsInOrder, id: \.self) { kind in
                Button {
                    model.setKind(kind, of: current)
                    close()
                } label: {
                    HStack(spacing: 10) {
                        StatusIcon(glyph: AppModel.kindGlyph(kind, color: current.color))
                            .frame(width: 18, height: 18)
                        Text(AppModel.statusTitle(kind))
                        Spacer(minLength: 8)
                        if current.statusCategory == kind {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(lit == kind ? Theme.menuHighlight : .clear))
                    .padding(.horizontal, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { lit = $0 ? kind : (lit == kind ? nil : lit) }
            }
            Text(.statusIconNote)
                .font(.small)
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 15)
                .padding(.top, 2)
            MenuDivider()
            heading(.colour)
            HStack(spacing: 0) {
                ForEach(Defaults.optionColors, id: \.self) { color in
                    let selected = current.color == color
                    Button {
                        model.setColor(color, of: current)
                    } label: {
                        Circle()
                            .fill(Theme.optionColor(color) ?? Theme.textTertiary)
                            .frame(width: 14, height: 14)
                            .overlay {
                                if selected {
                                    Circle().stroke(Theme.optionColor(color) ?? Theme.textTertiary, lineWidth: 1.5).frame(width: 20, height: 20)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(Defaults.colourName(color))
                    .accessibilityLabel(Defaults.colourName(color))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 9)
            .padding(.bottom, 4)
        }
        .padding(.vertical, 6)
        .frame(width: 236)
        .font(.ui)
        .foregroundStyle(Theme.text)
        .onKeyPress(.escape) {
            close()
            return .handled
        }
    }

    private func heading(_ title: LocalizedStringResource) -> some View {
        MenuHeading(Text(title))
    }
}
#endif
