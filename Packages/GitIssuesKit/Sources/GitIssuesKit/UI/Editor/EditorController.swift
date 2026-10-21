#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Markdown you read and edit in the same place, as in Notebook: a TextKit 1 text view whose storage holds the
/// Markdown exactly, styled so that it reads as GitHub draws it. Markdown punctuation shows only right next to a
/// resting caret, tables, diagrams and maths open into their source when the caret goes in, and checkboxes tick.
/// Unlike Notebook's, it sits in a page that scrolls (an issue, a dialog) and is as tall as its text.
@MainActor
final class EditorController: NSObject, @preconcurrency NSTextStorageDelegate, EditorLayoutSource {
    let storage: NSTextStorage
    let layoutManager: MarkdownLayoutManager
    let container: NSTextContainer
    /// The text view: AppKit's on the Mac, UIKit's on iPhone and iPad (`EditorController+AppKit`, `+UIKit`), both
    /// on TextKit 1 with the same storage, layout manager and container.
    let textView: MarkdownTextView

    private(set) var document = MarkdownParser.parse("")
    private var lineSignatures: [Int] = []
    /// Character ranges whose hidden punctuation is shown, because the caret is in or next to them.
    private(set) var revealed: [NSRange] = []
    /// The block the caret is in, if it shows its Markdown then (tables, maths, diagrams).
    private(set) var activeBlock: Int?
    private(set) var isLoading = false
    private var isApplyingStyle = false
    /// True while the editor changes the text itself, so its own changes aren't taken for typing.
    var isPerformingEdit = false
    /// True while the editor selects something exactly, which isn't grown to take Markdown whole (a new link's word, to
    /// type over).
    var selectsExactly = false
    /// Whether the text is read as it is typed in: see `InlineParser.spans`.
    private(set) var isTypingIn = false
    /// What the last press of Bold (or another style) took off, for the next press to put back.
    var unwrapped: MarkdownUnwrapped?
    /// Eases the text into its new look after an edit: bold thickens, a heading grows, typed marks fade in.
    let styleAnimator = MarkdownStyleAnimator()
    /// Unfolds the marks the caret comes to and folds away those it leaves.
    let revealAnimator = MarkdownRevealAnimator()
    /// Which marks of the lines the last edit styled again were hidden before it, for the marks it showed or hid to fold
    /// in or out (`updateReveal`).
    private var editedMarks: (scope: NSRange, hiddenBefore: IndexSet)?
    /// The start of the line whose heading #s were just typed on a touch keyboard: they show until the caret leaves the
    /// line, so you see which heading you typed.
    var typedHeading: Int?
    /// When Delete was last pressed in the text, which tells a key held down from one pressed again.
    var lastDeleteBackward: CFTimeInterval = 0
    /// For tests: marks show next to the caret as with a keyboard (true) or not, as on a touch keyboard (false).
    var marksShowOverride: Bool? {
        didSet { updateReveal() }
    }
    /// What the caret is in, for the buttons on the left of the bar above the keyboard.
    let caretContext = CaretContext()

    /// Whether the text can be changed. Text that is only read (a pull request, a comment) shows no Markdown and
    /// opens nothing for editing.
    var isEditable: Bool {
        didSet {
            guard oldValue != isEditable else { return }
            layoutManager.hidesEditingControls = !isEditable
            updateEditability()
            restyleAll()
        }
    }
    /// Whether checkboxes tick where the text is only read (a preview of an issue).
    var allowsChecking = false

    /// Called after every change you make (not for text set from outside).
    var onTextChange: () -> Void = {}
    /// The editor got or lost the keyboard focus.
    var onFocusChange: (Bool) -> Void = { _ in }
    /// The text may be taller or shorter now.
    var onHeightChange: () -> Void = {}
    /// Something in the text may be somewhere else now: it was laid out again, at another width or with a block open.
    var onLayoutChange: () -> Void = {}
    /// ⌘↵. Without it, ⌘↵ finishes editing as Escape does.
    var onSubmit: (() -> Void)?
    /// Escape. Without it, Escape finishes editing.
    var onEscape: (() -> Void)?
    /// Goes to the end of the title above the text, as if it were the line above: ↑ on the first line, ← or Delete
    /// at the very start. Without it, those keys stay in the text.
    var onBackToTitle: (() -> Void)?
    /// Opens a link that was clicked or tapped: in the browser, or wherever a test says.
    var openLink: (URL) -> Void = { Platform.open($0) }
    /// What ⌘↵ does, for the list of shortcuts a hardware keyboard shows on iPad.
    var submitTitle: LocalizedStringResource = .done

    #if os(iOS)
    /// The selection before the last change, which tells where the caret came from.
    var previousSelection = NSRange(location: 0, length: 0)
    /// True while the editor moves the selection itself, so it isn't corrected again.
    var isSettingSelection = false
    var isWaitingForTracking = false
    /// The editor's own record of changes, for undo (`EditorUndo+UIKit`).
    let undoStack = EditorUndoManager()
    var openStep: UndoStep?
    var isReplayingUndo = false
    /// The text as it was before the last change, which tells what a change removed.
    var shadowText = NSMutableString()
    /// What the Format panel shows: the style of the caret's line and the formatting it is in.
    let formatState = FormatState()
    /// The Format panel in place of the keyboard, made the first time Aa is tapped.
    var formatInput: UIView?
    /// The bar above the keyboard.
    var writingBar: UIView?
    #endif

    /// Lays the text out at widths other than the one it has, to tell how tall it would be there.
    private var measurer: (layout: MarkdownLayoutManager, container: NSTextContainer)?
    /// Characters whose glyphs are to be made again once the edit going on is over (`flushGlyphs`).
    private var pendingGlyphs: NSRange?
    private var isGlyphFlushScheduled = false

    init(isEditable: Bool) {
        self.isEditable = isEditable
        let storage = NSTextStorage()
        let layoutManager = MarkdownLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(layoutManager)
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        self.storage = storage
        self.layoutManager = layoutManager
        self.container = container
        #if os(macOS)
        textView = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 40), textContainer: container)
        #else
        textView = MarkdownTextView(frame: CGRect(x: 0, y: 0, width: 360, height: 40), textContainer: container)
        #endif
        super.init()
        layoutManager.hidesEditingControls = !isEditable
        configureTextView()
        storage.delegate = self
        layoutManager.source = self
        textView.controller = self
        styleAnimator.view = textView
        styleAnimator.onFrame = { [weak self] in self?.layoutChanged() }
        revealAnimator.view = textView
        revealAnimator.onConcealed = { [weak self] ranges in self?.invalidateGlyphs(in: ranges) }
        revealAnimator.onFrame = { [weak self] in self?.layoutChanged() }
        updateEditability()
    }

    var text: String { storage.string }
    var nsText: NSString { storage.string as NSString }

    // MARK: - Loading

    /// Shows a text, from the start, with nothing to undo.
    func load(text: String) {
        isLoading = true
        revealAnimator.cancel()
        editedMarks = nil
        typedHeading = nil
        revealed = []
        activeBlock = nil
        lineSignatures = []
        updateLayoutMode(for: (text as NSString).length)
        storage.beginEditing()
        storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: text)
        storage.endEditing()
        setSelection(NSRange(location: 0, length: 0))
        #if os(iOS)
        undoStack.clear()
        openStep = nil
        previousSelection = NSRange(location: 0, length: 0)
        layoutManager.selectedRanges = []
        #else
        clearUndo()
        #endif
        isLoading = false
        textView.textDidLoad()
        layoutChanged()
    }

    /// Takes in a new version of the text from GitHub or another device while you aren't typing in it. Only the part
    /// that differs is replaced, so the selection and what is on screen stay where they are.
    func reload(text: String) {
        let old = storage.string as NSString
        let new = text as NSString
        guard old as String != text else { return }
        guard old.length > 0 else { return load(text: text) }
        var prefix = 0
        let limit = min(old.length, new.length)
        while prefix < limit, old.character(at: prefix) == new.character(at: prefix) { prefix += 1 }
        var suffix = 0
        while suffix < limit - prefix, old.character(at: old.length - 1 - suffix) == new.character(at: new.length - 1 - suffix) { suffix += 1 }
        let range = NSRange(location: prefix, length: old.length - prefix - suffix)
        let replacement = new.substring(with: NSRange(location: prefix, length: new.length - prefix - suffix))
        let selection = self.selection
        let delta = (replacement as NSString).length - range.length
        var caret = selection
        if selection.location >= range.upperBound { caret.location += delta } else if selection.location > range.location { caret = NSRange(location: range.location + (replacement as NSString).length, length: 0) }
        isLoading = true
        preservingScroll {
            storage.beginEditing()
            storage.replaceCharacters(in: range, with: replacement)
            storage.endEditing()
            setSelection(NSRange(location: min(caret.location, storage.length), length: min(caret.length, max(0, storage.length - caret.location))))
        }
        #if os(iOS)
        undoStack.clear()
        openStep = nil
        #else
        clearUndo()
        #endif
        editedMarks = nil
        isLoading = false
        textView.textDidLoad()
        layoutChanged()
    }

    /// Texts up to a few thousand words are laid out whole, so nothing below changes size by surprise. Longer ones
    /// are laid out where you look, so every keystroke stays within a frame.
    static let wholeLayoutLimit = 20_000

    private func updateLayoutMode(for length: Int) {
        let partial = length > Self.wholeLayoutLimit
        if layoutManager.allowsNonContiguousLayout != partial { layoutManager.allowsNonContiguousLayout = partial }
    }

    // MARK: - Height

    /// How tall the text is at a width: the line it starts with even when it is empty.
    func contentHeight(forWidth width: CGFloat) -> CGFloat {
        let width = max(width, 1)
        let minimum = EditorStyle.lineHeight
        guard storage.length > 0 else { return minimum }
        // TextKit leaves out the spacing after the last paragraph, where a diagram or formula being edited shows its
        // preview.
        var after: CGFloat = 0
        if nsText.character(at: storage.length - 1) != 10 {
            after = (storage.attribute(.paragraphStyle, at: storage.length - 1, effectiveRange: nil) as? NSParagraphStyle)?.paragraphSpacing ?? 0
        }
        if abs(container.size.width - width) < 0.5 {
            layoutManager.ensureLayout(for: container)
            return ceil(max(layoutManager.usedRect(for: container).height + after, minimum))
        }
        let measurer = self.measurer ?? {
            let layout = MarkdownLayoutManager()
            layout.source = self
            layout.hidesEditingControls = layoutManager.hidesEditingControls
            let container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
            container.lineFragmentPadding = 0
            layout.addTextContainer(container)
            storage.addLayoutManager(layout)
            self.measurer = (layout, container)
            return (layout, container)
        }()
        measurer.layout.hidesEditingControls = layoutManager.hidesEditingControls
        if measurer.container.size.width != width { measurer.container.size = NSSize(width: width, height: .greatestFiniteMagnitude) }
        measurer.layout.ensureLayout(for: measurer.container)
        return ceil(max(measurer.layout.usedRect(for: measurer.container).height + after, minimum))
    }

    /// The text was laid out again: it may have another height, and what is drawn in it other places.
    func layoutChanged() {
        onHeightChange()
        onLayoutChange()
    }

    /// A checkbox drawn in the text, for VoiceOver and UI tests, which can't see into what the text view draws.
    struct CheckboxPlace: Equatable, Identifiable {
        var line: Int
        /// In the text view's coordinates: the box and the height of its line.
        var frame: CGRect
        /// The item's text, without its Markdown.
        var label: String
        var isChecked: Bool
        var id: Int { line }
    }

    func checkboxPlaces() -> [CheckboxPlace] {
        guard storage.length > 0 else { return [] }
        layoutManager.ensureLayout(for: container)
        return document.checkboxes.compactMap { index, item in
            guard let box = item.checkbox, let rect = layoutManager.rect(forObjectAt: box.location, origin: textOrigin) else { return nil }
            let line = layoutManager.lineFragmentRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: box.location), effectiveRange: nil)
            let label = InlineRenderer.render(nsText.substring(with: document.lines[index].content), font: EditorStyle.body, color: EditorTheme.text).string
            return CheckboxPlace(
                line: index,
                frame: CGRect(x: rect.minX, y: line.minY + textOrigin.y, width: EditorStyle.checkboxWidth, height: line.height),
                label: label,
                isChecked: item.checked
            )
        }
    }

    // MARK: - Parsing and styling

    var environment: StyleEnvironment {
        StyleEnvironment(
            activeBlock: activeBlock,
            isEditable: isEditable,
            isDark: isDarkAppearance,
            previewHeight: { [weak self] block in self?.previewHeight(for: block) ?? 0 }
        )
    }

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters), !isApplyingStyle else { return }
        #if os(iOS)
        let oldRange = NSRange(location: editedRange.location, length: editedRange.length - delta)
        let removed = shadowText.substring(with: oldRange)
        shadowText.replaceCharacters(in: oldRange, with: (textStorage.string as NSString).substring(with: editedRange))
        recordChange(editedRange, removed: removed)
        #endif
        updateLayoutMode(for: textStorage.length)
        #if os(macOS)
        // Like the pointer, the copy button keeps out of the way while you type, and it would be left behind by a
        // block that moved.
        updateCopyButton(at: nil)
        #endif
        let oldDocument = document
        let oldSignatures = lineSignatures
        document = MarkdownParser.parse(storage.mutableString, typing: isTypingIn)
        // Keep the revealed punctuation where it was until the caret settles, moved along with the edit.
        let oldEnd = editedRange.location + editedRange.length - delta
        let oldRevealed = revealed
        revealed = revealed.compactMap { range in
            if range.upperBound <= editedRange.location { return range }
            if range.location >= oldEnd { return range.shifted(by: delta) }
            let start = min(range.location, editedRange.location)
            let end = min(storage.length, max(range.upperBound + delta, editedRange.upperBound))
            return end > start ? NSRange(location: start, length: end - start) : nil
        }
        // The open block is the one being typed in, wherever its index moved to.
        if activeBlock != nil {
            let caret = min(editedRange.upperBound, storage.length)
            let line = document.lineIndex(containing: caret)
            if let block = document.lines[safe: line]?.block, document.blocks[block].isSwappable { activeBlock = block } else { activeBlock = nil }
        }
        if let typed = typedHeading, typed > editedRange.location { typedHeading = typed >= oldEnd ? typed + delta : nil }

        let signatures = computeSignatures()
        var lines: [Int] = []
        let lineDelta = document.lines.count - oldDocument.lines.count
        for index in document.lines.indices {
            let line = document.lines[index]
            var oldIndex: Int?
            if line.fullRange.upperBound <= editedRange.location {
                oldIndex = index
            } else if line.range.location >= editedRange.upperBound {
                oldIndex = index - lineDelta
            }
            if let oldIndex, oldIndex >= 0, oldIndex < oldSignatures.count, oldSignatures[oldIndex] == signatures[index] { continue }
            lines.append(index)
        }
        lineSignatures = signatures
        isApplyingStyle = true
        if let first = lines.min(), let last = lines.max() {
            let start = document.lines[first].fullRange.location
            let scope = NSRange(location: start, length: document.lines[last].fullRange.upperBound - start)
            if revealAnimator.isEnabled, !isLoading {
                editedMarks = (scope, hiddenMarks(in: scope, edited: editedRange, delta: delta, revealedBefore: oldRevealed))
            }
            revealAnimator.shift(edited: editedRange, delta: delta)
            styleAnimator.restyle(storage, edited: editedRange, scope: scope) {
                MarkdownStyler.style(storage, document: document, lines: lines, environment: environment)
                // The edit's own fixing ran before the styling, which undid it: an emoji got the text's font.
                storage.fixAttributes(in: scope)
            }
            revealAnimator.reapply(to: storage)
        } else {
            revealAnimator.shift(edited: editedRange, delta: delta)
        }
        isApplyingStyle = false
        invalidateGlyphs(of: lines)
    }

    /// Lines styled again get their glyphs made again: which characters are hidden is decided when glyphs are made,
    /// and a change of attributes alone, above all one made while the text view is in the middle of its own edit,
    /// leaves the old ones (a table's source stayed hidden after it opened again).
    private func invalidateGlyphs(of lines: [Int]) {
        guard let first = lines.min(), let last = lines.max(), last < document.lines.count else { return }
        let start = document.lines[first].fullRange.location
        let range = NSRange(location: start, length: min(storage.length, document.lines[last].fullRange.upperBound) - start)
        guard range.length > 0 else { return }
        pendingGlyphs = pendingGlyphs.map { NSUnionRange($0, range) } ?? range
        flushGlyphs()
    }

    /// The lines of these ranges get their glyphs made again (marks that finished folding away hide).
    func invalidateGlyphs(in ranges: [NSRange]) {
        for range in ranges where range.upperBound <= storage.length {
            let line = nsText.lineRange(for: range)
            guard line.length > 0 else { continue }
            pendingGlyphs = pendingGlyphs.map { NSUnionRange($0, line) } ?? line
        }
        flushGlyphs()
    }

    /// Makes the glyphs waiting for it again, once no edit of the text is open: the layout manager may not be asked to
    /// lay out while the text storage is still processing one (UIKit throws).
    func flushGlyphs() {
        guard let pending = pendingGlyphs else { return }
        guard storage.editedMask.isEmpty else {
            if !isGlyphFlushScheduled {
                isGlyphFlushScheduled = true
                DispatchQueue.main.async { [weak self] in
                    self?.isGlyphFlushScheduled = false
                    self?.flushGlyphs()
                }
            }
            return
        }
        pendingGlyphs = nil
        let range = NSIntersectionRange(pending, NSRange(location: 0, length: storage.length))
        guard range.length > 0 else { return }
        for layout in [layoutManager, measurer?.layout].compactMap({ $0 }) {
            layout.invalidateGlyphs(forCharacterRange: range, changeInLength: 0, actualCharacterRange: nil)
            layout.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
        }
        layoutManager.invalidateDisplay(forCharacterRange: range)
    }

    /// What decides how a line looks: its text, what kind of line it is, the block it is in and whether that block is
    /// being edited. Lines whose signature didn't change keep their attributes.
    private func computeSignatures() -> [Int] {
        var blockHashes: [Int] = []
        for (index, block) in document.blocks.enumerated() {
            var hasher = Hasher()
            for line in block.lines { hasher.combine(document.lines[line].textHash) }
            hasher.combine(index == activeBlock)
            hasher.combine(block.kind)
            blockHashes.append(hasher.finalize())
        }
        return document.lines.enumerated().map { index, line in
            var hasher = Hasher()
            hasher.combine(line.textHash)
            Self.combineShape(of: line, into: &hasher)
            if let block = line.block {
                hasher.combine(blockHashes[block])
                hasher.combine(index - document.blocks[block].lines.lowerBound)
            }
            hasher.combine(index == 0)
            return hasher.finalize()
        }
    }

    /// A line's kind without where it is in the text, so lines that only moved don't count as changed.
    private static func combineShape(of line: MarkdownLine, into hasher: inout Hasher) {
        let start = line.range.location
        func relative(_ range: NSRange) -> Int { (range.location - start) << 16 | range.length }
        switch line.kind {
        case .heading(let level, let marker):
            hasher.combine(1); hasher.combine(level); hasher.combine(relative(marker))
        case .listItem(let item):
            hasher.combine(2); hasher.combine(item.indent); hasher.combine(item.level); hasher.combine(item.marker)
            hasher.combine(relative(item.markerRange)); hasher.combine(relative(item.prefix)); hasher.combine(item.checked)
            hasher.combine(item.checkbox.map(relative) ?? -1)
        case .quote(let depth, let prefix):
            hasher.combine(3); hasher.combine(depth); hasher.combine(relative(prefix))
        case .footnoteDefinition(let label):
            hasher.combine(4); hasher.combine(relative(label))
        case .blank: hasher.combine(10)
        case .paragraph: hasher.combine(11)
        case .thematicBreak: hasher.combine(12)
        case .fence: hasher.combine(13)
        case .code: hasher.combine(14)
        case .mathDelimiter: hasher.combine(15)
        case .math: hasher.combine(16)
        case .tableHeader: hasher.combine(17)
        case .tableDelimiter: hasher.combine(18)
        case .tableRow: hasher.combine(19)
        case .comment: hasher.combine(20)
        }
    }

    /// Styles lines again outside of an edit (the caret entered a block, a diagram turned out not to draw).
    func restyle(lines: [Int]) {
        guard !lines.isEmpty else { return }
        // An ease still under way would overwrite the new look with the old one's last.
        styleAnimator.complete()
        isApplyingStyle = true
        storage.beginEditing()
        MarkdownStyler.style(storage, document: document, lines: lines, environment: environment)
        revealAnimator.reapply(to: storage)
        if let first = lines.min(), let last = lines.max(), last < document.lines.count {
            let start = document.lines[first].fullRange.location
            storage.fixAttributes(in: NSRange(location: start, length: document.lines[last].fullRange.upperBound - start))
        }
        storage.endEditing()
        isApplyingStyle = false
        lineSignatures = computeSignatures()
        invalidateGlyphs(of: lines)
    }

    /// The whole text styled again: for the other appearance, another text size, or editing turned on or off.
    func restyleAll() {
        guard storage.length > 0 else { return }
        textView.typingAttributes = MarkdownStyler.baseAttributes
        preservingScroll {
            restyle(lines: Array(document.lines.indices))
            layoutManager.invalidateLayout(forCharacterRange: NSRange(location: 0, length: storage.length), actualCharacterRange: nil)
        }
        textNeedsDisplay()
        layoutChanged()
    }

    func lines(of block: Int) -> [Int] {
        guard let block = document.blocks[safe: block] else { return [] }
        return Array(block.lines)
    }

    private func previewHeight(for block: MarkdownBlock) -> CGFloat {
        let width = container.size.width
        switch block.kind {
        case .mermaid:
            let source = MarkdownStyler.diagramSource(nsText, document, block)
            if case .some(.some(let image)) = DiagramStore.diagram(source, isDark: isDarkAppearance, ready: { [weak self] in
                guard let self, let index = self.document.blocks.firstIndex(where: { $0.range == block.range }) else { return }
                self.preservingScroll { self.restyle(lines: self.lines(of: index)) }
                self.layoutChanged()
            }) {
                let scale = image.size.width > width ? width / image.size.width : 1
                return ceil(image.size.height * scale)
            }
            return 80
        case .math:
            let tex = MarkdownStyler.mathSource(nsText, document, block)
            if let math = MathStore.render(tex, display: true, size: (EditorStyle.bodySize * 1.3).rounded(), color: EditorTheme.text.resolvedColor(dark: isDarkAppearance)) {
                return ceil(math.image.size.height)
            }
            return 30
        default:
            return 0
        }
    }

    // MARK: - Revealing Markdown next to the caret

    /// The punctuation to show and the block to open for the caret where it is: none while text is selected, the
    /// text isn't focused or can't be edited.
    func revealTarget() -> (ranges: [NSRange], block: Int?) {
        let selection = self.selection
        guard isEditable, isFocused, !document.lines.isEmpty else { return ([], nil) }
        // While text is selected nothing appears or disappears, so the selection never moves under the pointer:
        // what showed next to the caret before stays until the caret rests somewhere again.
        if selection.length > 0 { return (revealed, activeBlock) }
        let caret = selection.location
        let lineIndex = document.lineIndex(containing: caret)
        let line = document.lines[lineIndex]
        var ranges: [NSRange] = []
        var block: Int?
        if let index = line.block {
            let found = document.blocks[index]
            if found.isSwappable { block = index }
            if case .code = found.kind { ranges.append(found.range) }
            if case .mermaid = found.kind { ranges.append(found.range) }
            if case .comment = found.kind { ranges.append(found.range) }
            if case .callout = found.kind, lineIndex == found.lines.lowerBound { ranges.append(line.range) }
        }
        switch line.kind {
        case .heading(_, let marker): if showsHeadingMarks(marker, of: line) { ranges.append(marker) }
        case .thematicBreak: ranges.append(line.range)
        default: break
        }
        for span in line.spans where !isAtomic(span) && span.range.touches(caret) {
            // On a touch keyboard the bar above it shows the styles the caret is in and turns them off.
            if !showsMarks, span.isStyle { continue }
            ranges.append(span.range)
        }
        return (merged(ranges), block)
    }

    /// Whether marks show next to the caret: with a keyboard, which reaches them with the arrow keys and deletes them
    /// with ease (the Mac, an iPad or iPhone with a keyboard attached). On a touch keyboard the bar above it turns
    /// styles on and off, and only marks being typed show.
    var showsMarks: Bool {
        if let marksShowOverride { return marksShowOverride }
        #if os(macOS)
        return true
        #else
        return HardwareKeyboard.shared.isInUse
        #endif
    }

    /// A heading's #s show while the caret is on it with a keyboard; on a touch keyboard while they are typed, until
    /// the caret leaves the line.
    private func showsHeadingMarks(_ marker: NSRange, of line: MarkdownLine) -> Bool {
        if showsMarks || typedHeading == line.range.location { return true }
        // Without their space yet, they are being typed.
        guard marker.length > 0 else { return false }
        let last = nsText.character(at: marker.upperBound - 1)
        return last != 32 && last != 9
    }

    private func merged(_ ranges: [NSRange]) -> [NSRange] {
        let sorted = ranges.filter { $0.length > 0 }.sorted { $0.location < $1.location }
        var result: [NSRange] = []
        for range in sorted {
            if let last = result.last, range.location <= last.upperBound {
                result[result.count - 1] = NSUnionRange(last, range)
            } else {
                result.append(range)
            }
        }
        return result
    }

    func isRevealed(_ characterIndex: Int) -> Bool {
        Self.contains(revealed, characterIndex) || revealAnimator.isConcealing(characterIndex)
    }

    /// Whether sorted ranges that don't overlap contain an index.
    private static func contains(_ ranges: [NSRange], _ index: Int) -> Bool {
        var low = 0, high = ranges.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let range = ranges[mid]
            if index < range.location { high = mid - 1 } else if index >= range.upperBound { low = mid + 1 } else { return true }
        }
        return false
    }

    /// Shows the punctuation next to the caret and opens the block it is in, keeping the caret's line still on screen.
    /// Marks that come or go fold in or out.
    func updateReveal(anchor: Int? = nil) {
        guard !isLoading, !isTracking else { return }
        let target = revealTarget()
        let edited = editedMarks
        editedMarks = nil
        guard target.ranges != revealed || target.block != activeBlock || edited != nil else { return }
        let blockChanged = target.block != activeBlock
        preservingScroll(anchor: anchor) {
            let old = revealed
            revealed = target.ranges
            if blockChanged {
                let previous = activeBlock
                activeBlock = target.block
                var lines: [Int] = []
                if let previous { lines += self.lines(of: previous) }
                if let block = target.block { lines += self.lines(of: block) }
                restyle(lines: lines)
            }
            let folding = foldingMarks(from: old, to: revealed, edited: edited)
            revealAnimator.animate(appearing: folding.appearing, disappearing: folding.disappearing, in: storage)
            for range in old + target.ranges + folding.appearing + folding.disappearing where range.upperBound <= storage.length {
                let lineRange = nsText.lineRange(for: range)
                layoutManager.invalidateGlyphs(forCharacterRange: lineRange, changeInLength: 0, actualCharacterRange: nil)
                layoutManager.invalidateLayout(forCharacterRange: lineRange, actualCharacterRange: nil)
                layoutManager.invalidateDisplay(forCharacterRange: lineRange)
            }
        }
        if blockChanged { layoutChanged() }
    }

    /// The marks in the lines an edit is about to style again that were hidden before it, where they are after it.
    /// What was typed showed as it was typed; what came in all at once (pasted, undone) counts as hidden, so it
    /// doesn't fold away mark by mark.
    private func hiddenMarks(in scope: NSRange, edited: NSRange, delta: Int, revealedBefore: [NSRange]) -> IndexSet {
        var hidden = IndexSet()
        let scope = NSIntersectionRange(scope, NSRange(location: 0, length: storage.length))
        // Not styled yet, the new text has whatever attributes it came with: all of it counts as one or the other.
        if edited.length > 12 { hidden.insert(integersIn: edited.location..<edited.upperBound) }
        storage.enumerateAttribute(.markdownHidden, in: scope) { value, run, _ in
            guard let mode = value as? Int else { return }
            for index in run.location..<run.upperBound where !NSLocationInRange(index, edited) {
                // Where the character was before the edit.
                let old = index < edited.location ? index : index - delta
                if mode == HiddenMode.always.rawValue || !(Self.contains(revealedBefore, old) || revealAnimator.isConcealing(old)) {
                    hidden.insert(index)
                }
            }
        }
        return hidden
    }

    /// The marks that come and go between two sets of revealed ranges, and those an edit showed or hid, as runs to fold
    /// in and out.
    private func foldingMarks(from old: [NSRange], to new: [NSRange], edited: (scope: NSRange, hiddenBefore: IndexSet)?) -> (appearing: [NSRange], disappearing: [NSRange]) {
        guard revealAnimator.isEnabled else { return ([], []) }
        var candidates = IndexSet()
        for range in old + new + [edited?.scope].compactMap({ $0 }) where range.length > 0 {
            candidates.insert(integersIn: range.location..<min(range.upperBound, storage.length))
        }
        var appearing = IndexSet()
        var disappearing = IndexSet()
        for run in candidates.rangeView {
            storage.enumerateAttribute(.markdownHidden, in: NSRange(location: run.lowerBound, length: run.count)) { value, range, _ in
                guard (value as? Int) == HiddenMode.untilRevealed.rawValue else { return }
                for index in range.location..<range.upperBound {
                    let before = edited.map { NSLocationInRange(index, $0.scope) ? !$0.hiddenBefore.contains(index) : nil } ?? nil
                    let shownBefore = before ?? Self.contains(old, index)
                    let shown = Self.contains(new, index)
                    if shown, !shownBefore { appearing.insert(index) }
                    if !shown, shownBefore { disappearing.insert(index) }
                }
            }
        }
        func runs(_ set: IndexSet) -> [NSRange] { set.rangeView.map { NSRange(location: $0.lowerBound, length: $0.count) } }
        return (runs(appearing), runs(disappearing))
    }

    // MARK: - Keeping what you look at in place

    /// Runs a change that may make lines taller or shorter and scrolls the page the text is in so that the caret (or
    /// the top line, when the caret is off screen) stays exactly where it was on screen.
    func preservingScroll(anchor: Int? = nil, _ change: () -> Void) {
        guard isInWindow, storage.length > 0, hasScroller else { change(); return }
        let visible = visibleRect
        guard visible.height > 0 else { change(); return }
        var index = anchor ?? selection.location
        // Laid out first: right after an edit the lines below it may not be yet, and the caret on a new line would
        // be measured where the line above it was (Return after a heading scrolled the page by a line).
        layoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: min(storage.length, index + 1)))
        var y = yPosition(of: index)
        if anchor == nil, y < visible.minY || y > visible.maxY {
            index = firstVisibleCharacter(in: visible)
            y = yPosition(of: index)
        }
        let before = screenY(y)
        change()
        layoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: min(storage.length, index + 1)))
        let delta = screenY(yPosition(of: index)) - before
        if abs(delta) > 0.5 { scrollPage(by: delta) }
    }

    func yPosition(of index: Int) -> CGFloat {
        guard storage.length > 0 else { return textOrigin.y }
        let glyph = layoutManager.glyphIndexForCharacter(at: min(index, storage.length - 1))
        guard glyph < layoutManager.numberOfGlyphs else { return textOrigin.y }
        if index >= storage.length, layoutManager.extraLineFragmentTextContainer != nil {
            return layoutManager.extraLineFragmentRect.minY + textOrigin.y
        }
        return layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY + textOrigin.y
    }

    private func firstVisibleCharacter(in visible: NSRect) -> Int {
        let point = NSPoint(x: visible.minX + 1, y: max(0, visible.minY - textOrigin.y + 1))
        let glyph = layoutManager.glyphIndex(for: point, in: container)
        return layoutManager.characterIndexForGlyph(at: glyph)
    }

    // MARK: - EditorLayoutSource

    func objectNeedsDisplay(_ range: NSRange) {
        guard range.upperBound <= storage.length else { return }
        layoutManager.invalidateDisplay(forCharacterRange: range)
    }

    /// A diagram or picture arrived: the block it is in is styled again (a diagram that can't be drawn shows its
    /// code instead) and laid out at its size.
    func objectNeedsLayout(_ range: NSRange) {
        guard range.upperBound <= storage.length, !document.lines.isEmpty else { return }
        let first = document.lineIndex(containing: range.location)
        let last = document.lineIndex(containing: max(range.location, range.upperBound - 1))
        preservingScroll {
            restyle(lines: Array(first...last))
            layoutManager.invalidateLayout(forCharacterRange: nsText.lineRange(for: range), actualCharacterRange: nil)
            layoutManager.invalidateDisplay(forCharacterRange: nsText.lineRange(for: range))
        }
        layoutChanged()
    }

    // MARK: - Selection and focus

    /// The selection moved: show the Markdown next to the caret.
    func selectionChanged() {
        flushGlyphs()
        layoutManager.selectedRanges = selectedRanges
        // The #s typed on a touch keyboard go once the caret is on another line.
        if let typed = typedHeading, document.lines.isEmpty || document.lines[document.lineIndex(containing: selection.location)].range.location != typed {
            typedHeading = nil
        }
        if !isTracking { updateReveal() }
        textNeedsDisplay()
        updateCaretContext()
    }

    func textChanged() {
        flushGlyphs()
        guard !isLoading else { return }
        // An edit that didn't move the caret: the marks it showed or hid fold in or out now.
        if editedMarks != nil, !isTracking { updateReveal() }
        textView.textDidChangeContent()
        onTextChange()
        layoutChanged()
        updateCaretContext()
    }

    func mouseTrackingEnded() {
        layoutManager.selectedRanges = selectedRanges
        updateReveal()
    }

    /// The text view got or lost the keyboard focus. Told by the text view itself: while AppKit's resigns, the window
    /// still has it as its first responder.
    func focusChanged(to hasFocus: Bool) {
        // Selecting text that is only read takes the focus too, but isn't editing it.
        let focused = hasFocus && isEditable
        MarkdownFocus.shared.focusChanged(textView, to: focused)
        if !focused { unwrapped = nil }
        if isTypingIn != focused { readForTyping(focused) }
        onFocusChange(focused)
        updateCaretContext()
        DispatchQueue.main.async { [weak self] in
            self?.updateReveal()
        }
    }

    /// Reads the text again for typing in it or for reading it, and styles the lines that read differently now.
    private func readForTyping(_ typing: Bool) {
        isTypingIn = typing
        let old = document
        document = MarkdownParser.parse(storage.mutableString, typing: typing)
        let changed = document.lines.indices.filter { $0 >= old.lines.count || old.lines[$0].spans != document.lines[$0].spans }
        if !changed.isEmpty { restyle(lines: changed) }
    }

    // MARK: - Caret

    /// The caret drawn from the baseline up to the top of the text, rather than over the whole line.
    func caretRect(proposed rect: NSRect) -> NSRect {
        let selection = self.selection
        guard selection.length == 0, storage.length > 0, let line = caretLine(of: selection.location, at: rect.midY) else {
            return shortCaret(rect, line: rect, font: EditorStyle.body)
        }
        let index = selection.location
        guard let character = line.character else {
            // An empty line: the caret where its text will go.
            return shortCaret(rect, line: line.used, font: index < storage.length ? font(at: index) : EditorStyle.body)
        }
        let glyph = layoutManager.glyphIndexForCharacter(at: character)
        let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let baseline = textOrigin.y + fragment.minY + layoutManager.location(forGlyphAt: glyph).y
        return caret(rect, baseline: baseline, font: font(at: character))
    }

    /// The line the caret is on: the part of it its text takes, without the spacing around it, and the character the
    /// caret takes its height from, the nearest one shown on the line, the one after the caret first. Line breaks and
    /// hidden Markdown aren't laid out on the baseline, and an empty line has none.
    private func caretLine(of index: Int, at y: CGFloat) -> (used: NSRect, character: Int?)? {
        guard layoutManager.numberOfGlyphs > 0 else { return nil }
        let glyph = layoutManager.glyphIndex(for: NSPoint(x: 0, y: y - textOrigin.y), in: container)
        var glyphs = NSRange()
        let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &glyphs)
        guard y >= textOrigin.y + line.minY, y < textOrigin.y + line.maxY else {
            // Below the last line, on the empty one after a final line break.
            guard layoutManager.extraLineFragmentTextContainer != nil else { return nil }
            return (layoutManager.extraLineFragmentUsedRect.offsetBy(dx: textOrigin.x, dy: textOrigin.y), nil)
        }
        let used = layoutManager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil).offsetBy(dx: textOrigin.x, dy: textOrigin.y)
        let characters = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let caret = min(max(index, characters.location), NSMaxRange(characters))
        let after = caret..<NSMaxRange(characters)
        let nearest = Array(after.prefix(1)) + (characters.location..<caret).reversed() + after.dropFirst()
        return (used, nearest.first { nsText.character(at: $0) != 10 && !layoutManager.isHidden($0) && layoutManager.object(at: $0) == nil })
    }

    private func font(at index: Int) -> NSFont {
        let font = storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont
        return font.map { $0.pointSize < 4 ? EditorStyle.body : $0 } ?? EditorStyle.body
    }

    /// The caret where text in this font would sit on a line without any: TextKit puts the baseline the font's descent
    /// above the bottom of the line's text, and `EditorStyle.baselineOffset` lifts it from there.
    private func shortCaret(_ rect: NSRect, line: NSRect, font: NSFont) -> NSRect {
        #if os(macOS)
        // AppKit lays text out with the font's metrics rounded to whole points.
        let descent = layoutManager.defaultLineHeight(for: font) - layoutManager.defaultBaselineOffset(for: font)
        #else
        let descent = -font.descender
        #endif
        let baseline = line.maxY - descent - EditorStyle.baselineOffset(for: font, lineHeight: line.height)
        return caret(rect, baseline: baseline, font: font)
    }

    /// From a point above the font's ascender to a point below its descender.
    private func caret(_ rect: NSRect, baseline: CGFloat, font: NSFont) -> NSRect {
        fitted(NSRect(x: rect.minX, y: baseline - font.ascender - 1, width: rect.width, height: font.ascender - font.descender + 2), in: rect)
    }

    /// Kept inside the caret the text view proposed. On the Mac only that is redrawn when the caret blinks, so a caret
    /// reaching past it leaves a piece of itself on screen.
    private func fitted(_ caret: NSRect, in rect: NSRect) -> NSRect {
        let height = min(caret.height, rect.height)
        return NSRect(x: caret.minX, y: min(max(caret.minY, rect.minY), rect.maxY - height), width: caret.width, height: height)
    }
}

