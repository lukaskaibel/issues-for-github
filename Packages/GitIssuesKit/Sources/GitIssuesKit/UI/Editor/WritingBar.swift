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

/// The bar above the keyboard while you write, as in Notebook and Notes: the tools float over the page in a capsule
/// of glass, a little above the keyboard, and the ones that don't fit wait on the next page. Done, next to it, is
/// always in reach.
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

    /// The capsule spans the screen on an iPhone, less its margins and Done; on a wider screen it stops at about ten
    /// tools.
    static func barWidth(for available: CGFloat) -> CGFloat {
        max(toolWidth, min(available - 24 - barHeight - spacing, 560))
    }

    private let host: UIHostingController<WritingBarView>

    init(editor: EditorController) {
        host = UIHostingController(rootView: WritingBarView(editor: editor))
        super.init(frame: CGRect(x: 0, y: 0, width: 400, height: Self.height))
        autoresizingMask = [.flexibleWidth]
        backgroundColor = .clear
        host.view.backgroundColor = .clear
        host.safeAreaRegions = []
        host.view.frame = bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(host.view)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: Self.height) }

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
            let width = WritingBar.barWidth(for: proxy.size.width)
            let pages = Self.pages(of: WritingTool.allCases, width: width)
            let perPage = pages.first?.count ?? 1
            HStack(spacing: WritingBar.spacing) {
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
