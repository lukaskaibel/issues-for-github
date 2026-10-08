import MarkdownUI
import SwiftUI

/// GitHub-flavoured Markdown, rendered natively in the app's type and colours: tables, checklists, code and
/// Mermaid diagrams included. Single line breaks stay, as GitHub keeps them in issues and comments.
struct MarkdownText: View {
    var text: String
    var fontSize: CGFloat = 14
    var isSelectable = true
    /// Given, the checkboxes can be ticked; it gets the whole text with one box changed.
    var onChange: ((String) -> Void)?

    var body: some View {
        let document = MarkdownDocument(text)
        let markdown = Markdown(document.rendered(taggingCheckboxes: onChange != nil))
            .markdownTheme(Self.theme)
            .markdownTextStyle(\.text) {
                ForegroundColor(Self.textColor)
                FontSize(fontSize)
            }
            .markdownSoftBreakMode(.lineBreak)
            .environment(\.markdownCheckboxToggle, onChange.map { change in CheckboxToggle { change(document.toggling($0)) } })
            .frame(maxWidth: .infinity, alignment: .leading)
        if isSelectable {
            markdown.textSelection(.enabled)
        } else {
            markdown
        }
    }

    fileprivate static let textColor = Color(light: 0x2E3035, dark: 0xC9CCD1)
    fileprivate static let strongColor = Color(light: 0x1A1B1E, dark: 0xE8E9EB)
    fileprivate static let muted = Color(light: 0x5F636B, dark: 0x9A9FA8)
    fileprivate static let accent = Color(light: 0x4F57C9, dark: 0x8F96F2)
    fileprivate static let codeBackground = Color(light: 0xF0F1F4, dark: 0x1B1D21)
    fileprivate static let rule = Color(light: 0xDCDDE2, dark: 0x2A2D33)
    fileprivate static let stripe = Color(light: 0xF5F6F8, dark: 0x16171A)

    private static let theme = MarkdownUI.Theme()
        .text {
            ForegroundColor(textColor)
            FontSize(14)
        }
        .strong {
            FontWeight(.semibold)
            ForegroundColor(strongColor)
        }
        .link {
            ForegroundColor(accent)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.9))
            BackgroundColor(codeBackground)
        }
        .paragraph { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .relativeLineSpacing(.em(0.24))
                .markdownMargin(top: 0, bottom: 12)
        }
        .heading1 { configuration in
            configuration.label
                .markdownMargin(top: 20, bottom: 10)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.45))
                    ForegroundColor(strongColor)
                }
        }
        .heading2 { configuration in
            configuration.label
                .markdownMargin(top: 18, bottom: 8)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.25))
                    ForegroundColor(strongColor)
                }
        }
        .heading3 { configuration in
            configuration.label
                .markdownMargin(top: 16, bottom: 8)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.1))
                    ForegroundColor(strongColor)
                }
        }
        .blockquote { configuration in
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 1.5).fill(rule).frame(width: 3)
                configuration.label
                    .markdownTextStyle { ForegroundColor(muted) }
                    .relativePadding(.leading, length: .em(0.9))
            }
            .fixedSize(horizontal: false, vertical: true)
            .markdownMargin(top: 0, bottom: 12)
        }
        .codeBlock { configuration in
            if MarkdownDocument.isDiagram(fenceInfo: configuration.language) {
                MermaidDiagram(source: configuration.content) {
                    CodeBlock(configuration: configuration)
                }
                .markdownMargin(top: 8, bottom: 16)
            } else {
                CodeBlock(configuration: configuration)
            }
        }
        .listItem { configuration in
            ListItem(configuration: configuration)
        }
        .taskListMarker { configuration in
            Checkbox(isChecked: configuration.isCompleted)
        }
        .table { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .markdownTableBorderStyle(.init(color: rule))
                .markdownTableBackgroundStyle(.alternatingRows(Color.clear, stripe))
                .markdownMargin(top: 0, bottom: 14)
        }
        .tableCell { configuration in
            configuration.label
                .markdownTextStyle {
                    if configuration.row == 0 {
                        FontWeight(.semibold)
                        ForegroundColor(strongColor)
                    }
                    FontSize(.em(0.93))
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .relativeLineSpacing(.em(0.2))
        }
        .thematicBreak {
            Divider().overlay(rule).markdownMargin(top: 16, bottom: 16)
        }
}

/// Ticks or unticks a checkbox of the Markdown being drawn, by its number.
struct CheckboxToggle {
    var action: (Int) -> Void
    func callAsFunction(_ number: Int) { action(number) }
}

extension EnvironmentValues {
    /// Nil where checkboxes can't be ticked.
    @Entry var markdownCheckboxToggle: CheckboxToggle?
    /// The checkbox the list item being drawn starts with.
    @Entry fileprivate var markdownCheckbox: CheckboxItem?
}

private struct CheckboxItem {
    var number: Int
    /// The item's text, which names the box for VoiceOver.
    var label: String
}

private struct CodeBlock: View {
    var configuration: CodeBlockConfiguration

    var body: some View {
        ScrollView(.horizontal) {
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .relativeLineSpacing(.em(0.22))
                .markdownTextStyle {
                    FontFamilyVariant(.monospaced)
                    FontSize(.em(0.9))
                }
                .padding(12)
        }
        .background(MarkdownText.codeBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .markdownMargin(top: 0, bottom: 12)
    }
}

/// A list item, which tells its checkbox, if it has one, which one it is.
private struct ListItem: View {
    var configuration: BlockConfiguration
    @Environment(\.markdownCheckboxToggle) private var toggle

    var body: some View {
        configuration.label
            .markdownMargin(top: .em(0.25))
            .environment(\.markdownCheckbox, toggle == nil ? nil : checkbox)
    }

    private var checkbox: CheckboxItem? {
        guard let number = MarkdownDocument.checkboxNumber(inItem: configuration.content.renderMarkdown()) else { return nil }
        let text = configuration.content.renderPlainText()
        return CheckboxItem(number: number, label: String(text.prefix { !$0.isNewline }))
    }
}

private struct Checkbox: View {
    var isChecked: Bool
    @Environment(\.markdownCheckbox) private var item
    @Environment(\.markdownCheckboxToggle) private var toggle

    var body: some View {
        if let item, let toggle {
            Button {
                toggle(item.number)
            } label: {
                mark.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: isChecked)
            .accessibilityLabel(item.label)
            .accessibilityValue(state)
        } else {
            mark.accessibilityLabel(state)
        }
    }

    private var state: LocalizedStringResource {
        isChecked ? .checkboxChecked : .checkboxUnchecked
    }

    private var mark: some View {
        Image(systemName: isChecked ? "checkmark.square.fill" : "square")
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(isChecked ? MarkdownText.accent : MarkdownText.muted)
            .contentTransition(.symbolEffect(.replace))
            .imageScale(.small)
            .relativeFrame(minWidth: .em(1.5), alignment: .trailing)
    }
}
