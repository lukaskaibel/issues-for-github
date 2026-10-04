import MarkdownUI
import SwiftUI

/// GitHub-flavoured Markdown, rendered natively in the app's type and colours.
struct MarkdownText: View {
    var text: String

    var body: some View {
        Markdown(text)
            .markdownTheme(Self.theme)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static let textColor = Color(light: 0x2E3035, dark: 0xC9CCD1)
    private static let strongColor = Color(light: 0x1A1B1E, dark: 0xE8E9EB)
    private static let muted = Color(light: 0x5F636B, dark: 0x9A9FA8)
    private static let accent = Color(light: 0x4F57C9, dark: 0x8F96F2)
    private static let codeBackground = Color(light: 0xF0F1F4, dark: 0x1B1D21)
    private static let rule = Color(light: 0xDCDDE2, dark: 0x2A2D33)

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
            .background(codeBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .markdownMargin(top: 0, bottom: 12)
        }
        .listItem { configuration in
            configuration.label.markdownMargin(top: .em(0.25))
        }
        .thematicBreak {
            Divider().overlay(rule).markdownMargin(top: 16, bottom: 16)
        }
}
