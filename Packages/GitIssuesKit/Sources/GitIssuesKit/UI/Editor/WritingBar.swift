#if os(iOS)
import SwiftUI
import UIKit

/// What the bar above the keyboard holds, in this order: Notebook's bar, without what GitHub can't take (pictures,
/// drawings).
enum WritingTool: CaseIterable, Identifiable {
    case format, checklist, link, undo, redo
    case bold, italic, strikethrough, code, quote
    case bulletedList, numberedList, outdent, indent

    var id: Self { self }

    var command: FormatCommand? {
        switch self {
        case .checklist: .checklist
        case .link: .link
        case .bold: .bold
        case .italic: .italic
        case .strikethrough: .strikethrough
        case .code: .code
        case .quote: .quote
        case .bulletedList: .bulletedList
        case .numberedList: .numberedList
        case .outdent: .outdent
        case .indent: .indent
        default: nil
        }
    }

    var name: String {
        if let command { return command.name }
        switch self {
        case .format: return String(localized: .formatMenu)
        case .undo: return String(localized: .writingUndo)
        default: return String(localized: .writingRedo)
        }
    }

    var symbol: String {
        if let command { return command.symbol }
        switch self {
        case .format: return "textformat"
        case .undo: return "arrow.uturn.backward"
        default: return "arrow.uturn.forward"
        }
    }
}

/// A button on the left of the bar for where the caret is: a style it is in (on, tinted; a tap takes it off), the
/// checkbox of its line, moving its list item out or in, and opening the link it is on.
enum CaretTool: CaseIterable, Identifiable {
    case bold, italic, strikethrough, code, checkbox, outdent, indent, openLink

    var id: Self { self }

    var style: MarkdownSyntax.Style? {
        switch self {
        case .bold: .bold
        case .italic: .italic
        case .strikethrough: .strikethrough
        case .code: .code
        default: nil
        }
    }

    var name: String {
        switch self {
        case .bold: String(localized: .formatBold)
        case .italic: String(localized: .formatItalic)
        case .strikethrough: String(localized: .formatStrikethrough)
        case .code: String(localized: .formatCode)
        case .checkbox: String(localized: .formatCheckbox)
        case .outdent: String(localized: .formatOutdent)
        case .indent: String(localized: .formatIndent)
        case .openLink: String(localized: .formatOpenLink)
        }
    }

    func symbol(checked: Bool) -> String {
        switch self {
        case .bold: "bold"
        case .italic: "italic"
        case .strikethrough: "strikethrough"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .checkbox: checked ? "checkmark.square.fill" : "square"
        case .outdent: "decrease.indent"
        case .indent: "increase.indent"
        case .openLink: "arrow.up.right.square"
        }
    }

    /// The buttons for a place in the text, in the order they stand in.
    static func tools(for context: MarkdownEditing.Context) -> [CaretTool] {
        var tools = allCases.filter { $0.style.map(context.styles.contains) ?? false }
        if context.isChecklist { tools.append(.checkbox) }
        if context.canOutdent { tools.append(.outdent) }
        if context.canIndent { tools.append(.indent) }
        if context.link != nil { tools.append(.openLink) }
        return tools
    }
}

/// The bar above the keyboard while you write, as in Notebook and Notes: the tools float over the page in a capsule
/// of glass, a little above the keyboard, and the ones that don't fit wait on the next page. Done, next to it, is
/// always in reach. On the left, buttons for where the caret is come and go in a capsule of their own.
@MainActor
final class WritingBar: UIView {
    /// Room above the capsule, the capsule, and the gap between it and the keyboard.
    static let topGap: CGFloat = 6
    static let barHeight: CGFloat = 44
    static let keyboardGap: CGFloat = 10
    static let height = topGap + barHeight + keyboardGap
    /// About a fingertip per tool; a page holds as many as fit.
    static let toolWidth: CGFloat = 52
    static let spacing: CGFloat = 8
    /// The buttons for where the caret is, a little narrower, with a margin inside their capsule.
    static let caretToolWidth: CGFloat = 40
    static let caretMargin: CGFloat = 5

    /// The capsule spans the screen on an iPhone, less its margins and Done; on a wider screen it stops at about ten
    /// tools.
    static func barWidth(for available: CGFloat) -> CGFloat {
        max(toolWidth, min(available - 24 - barHeight - spacing, 560))
    }

    private let host: UIHostingController<WritingBarView>

    init(editor: EditorController) {
        host = UIHostingController(rootView: WritingBarView(editor: editor))
        super.init(frame: CGRect(x: 0, y: 0, width: 400, height: Self.height))
        // A height of its own, so that iOS takes the intrinsic one.
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        backgroundColor = .clear
        host.view.backgroundColor = .clear
        host.safeAreaRegions = []
        host.view.frame = CGRect(x: 0, y: 0, width: bounds.width, height: Self.height)
        host.view.autoresizingMask = [.flexibleWidth, .flexibleBottomMargin]
        addSubview(host.view)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// With a hardware keyboard the bar stands at the foot of the screen, where the home indicator is and iOS keeps
    /// touches for its own gestures: it stands above that, the strip below it left empty. Above the keyboard its
    /// safe area has nothing at the bottom.
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.height + safeAreaInsets.bottom)
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        invalidateIntrinsicContentSize()
    }

    /// Only the capsule and Done take touches: the strip around them belongs to the page.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let width = Self.barWidth(for: bounds.width) + Self.spacing + Self.barHeight
        let bar = CGRect(x: (bounds.width - width) / 2, y: Self.topGap, width: width, height: Self.barHeight)
        return bar.insetBy(dx: -4, dy: -4).contains(point)
    }
}

struct WritingBarView: View {
    let editor: EditorController
    @State private var page: Int? = 0

    var body: some View {
        GeometryReader { proxy in
            let full = WritingBar.barWidth(for: proxy.size.width)
            let context = editor.caretContext.context
            // As many as leave the tools room for two of theirs.
            let room = Int((full - 2 * WritingBar.toolWidth - WritingBar.spacing - 2 * WritingBar.caretMargin) / WritingBar.caretToolWidth)
            let caretTools = Array(CaretTool.tools(for: context).prefix(max(0, room)))
            let caretWidth = caretTools.isEmpty ? 0 : CGFloat(caretTools.count) * WritingBar.caretToolWidth + 2 * WritingBar.caretMargin
            let width = full - (caretTools.isEmpty ? 0 : caretWidth + WritingBar.spacing)
            let pages = Self.pages(of: WritingTool.allCases, width: width)
            let perPage = pages.first?.count ?? 1
            HStack(spacing: WritingBar.spacing) {
                if !caretTools.isEmpty {
                    HStack(spacing: 0) {
                        ForEach(caretTools) { tool in
                            caretButton(tool, checked: context.isChecked)
                                .transition(.scale(scale: 0.4).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, WritingBar.caretMargin)
                    .frame(width: caretWidth, height: WritingBar.barHeight)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .transition(.scale(scale: 0.4, anchor: .leading).combined(with: .opacity))
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(pages.indices, id: \.self) { index in
                            HStack(spacing: 0) {
                                ForEach(pages[index]) { tool in
                                    button(tool)
                                }
                                // The last page keeps the others' spacing.
                                ForEach(0..<max(0, perPage - pages[index].count), id: \.self) { _ in
                                    Color.clear.frame(maxWidth: .infinity)
                                }
                            }
                            .containerRelativeFrame(.horizontal)
                            .id(index)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollIndicators(.hidden)
                .scrollPosition(id: $page)
                .scrollDisabled(pages.count < 2)
                .frame(width: width, height: WritingBar.barHeight)
                .overlay(alignment: .bottom) {
                    if pages.count > 1 { dots(count: pages.count) }
                }
                .clipShape(.capsule)
                .glassEffect(.regular.interactive(), in: .capsule)

                // As tall as the bar: the glass button style would pad it larger.
                Button { editor.finishEditing() } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: WritingBar.barHeight, height: WritingBar.barHeight)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(Theme.accentFill).interactive(), in: .circle)
                .accessibilityLabel(Text(.done))
                .accessibilityIdentifier("writing-bar-done")
            }
            .frame(maxWidth: .infinity)
            .padding(.top, WritingBar.topGap)
            .animation(UIAccessibility.isReduceMotionEnabled ? nil : .spring(duration: Theme.keyboardBarSpring.duration, bounce: Theme.keyboardBarSpring.bounce), value: caretTools)
            // Fewer pages when the buttons for the caret take room: stay on one that is there.
            .onChange(of: pages.count) { _, count in
                if let current = page, current >= count { page = max(0, count - 1) }
            }
        }
    }

    /// A button for where the caret is. A style the caret is in shows as on, tinted.
    private func caretButton(_ tool: CaretTool, checked: Bool) -> some View {
        let isOn = tool.style != nil || (tool == .checkbox && checked)
        return Button { perform(tool) } label: {
            Image(systemName: tool.symbol(checked: checked))
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(isOn ? Theme.accent : Color.primary)
                .frame(width: WritingBar.caretToolWidth - 4, height: 36)
                .background { if tool.style != nil { Capsule().fill(Theme.accent.opacity(0.16)) } }
                .frame(width: WritingBar.caretToolWidth, height: WritingBar.barHeight)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tool.name)
        .accessibilityAddTraits(tool.style != nil ? .isSelected : [])
        .accessibilityValue(tool == .checkbox ? Text(checked ? .checkboxChecked : .checkboxUnchecked) : Text(verbatim: ""))
    }

    private func perform(_ tool: CaretTool) {
        if let style = tool.style { return editor.toggle(style) }
        switch tool {
        case .checkbox: editor.toggleChecked()
        case .outdent: editor.indent(by: -1)
        case .indent: editor.indent(by: 1)
        case .openLink: if let link = editor.caretContext.context.link { editor.openLink(link) }
        default: break
        }
    }

    static func pages<Tool>(of tools: [Tool], width: CGFloat) -> [[Tool]] {
        let perPage = max(1, Int(width / WritingBar.toolWidth))
        return stride(from: 0, to: tools.count, by: perPage).map { Array(tools[$0..<min($0 + perPage, tools.count)]) }
    }

    /// Which page of tools this is, small at the capsule's lower edge.
    private func dots(count: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(Color.primary.opacity(index == (page ?? 0) ? 0.5 : 0.15))
                    .frame(width: 4, height: 4)
            }
        }
        .padding(.bottom, 3)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func button(_ tool: WritingTool) -> some View {
        Button { perform(tool) } label: {
            Image(systemName: tool.symbol)
                .font(.system(size: 18))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.rect)
                .accessibilityLabel(tool.name)
        }
        .buttonStyle(.plain)
    }

    private func perform(_ tool: WritingTool) {
        if let command = tool.command { return editor.beginEditing(then: command) }
        switch tool {
        case .format: editor.toggleFormatPanel()
        case .undo: editor.textView.undoManager?.undo()
        default: editor.textView.undoManager?.redo()
        }
    }
}

extension EditorController {
    /// Does something at the caret from a button of the bar or the Format panel: the keyboard comes up as it would
    /// for a tap in the text.
    func beginEditing(then command: FormatCommand? = nil) {
        if !isFocused { makeTextFirstResponder() }
        if let command { perform(command) }
    }
}
#endif
