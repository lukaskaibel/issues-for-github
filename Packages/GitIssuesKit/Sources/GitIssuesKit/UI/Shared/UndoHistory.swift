import Foundation

/// What can be undone and redone, newest last. It works as a system undo manager does: what runs while undoing leaves
/// its own opposite on the redo side, and the other way round, so every step can go back and forth. `Action` is what a
/// step does when it runs.
struct UndoHistory<Action> {
    enum Mode: Equatable {
        case recording
        case undoing
        case redoing
    }

    struct Step: Identifiable {
        let id = UUID()
        var name: LocalizedStringResource
        /// Run first to last: what was done last is taken back first.
        var actions: [Action]
        /// Who else knows about this step: the notice or Inbox message that offers its Undo.
        var tag: UUID?
        /// Steps with the same key that follow each other are one: a description saved again while it is being written.
        var mergeKey: String?
        var recordedAt = Date()
    }

    /// How many steps are kept on each side.
    static var limit: Int { 100 }
    /// How long after the last save more of the same still belongs to the step.
    static var mergeWindow: TimeInterval { 120 }

    private(set) var undoSteps: [Step] = []
    private(set) var redoSteps: [Step] = []
    private(set) var mode = Mode.recording
    /// True from the first thing recorded until the moment is over: all that one key or click does is one step.
    private(set) var isGrouping = false
    private var running: Step?

    var nextUndo: Step? { undoSteps.last }
    var nextRedo: Step? { redoSteps.last }

    /// Notes what takes back something just done.
    mutating func record(
        _ actions: [Action], name: LocalizedStringResource, tag: UUID? = nil, mergeKey: String? = nil, now: Date = Date()
    ) {
        guard !actions.isEmpty else { return }
        switch mode {
        case .recording:
            redoSteps = []
            if let mergeKey, !isGrouping, let last = undoSteps.last, last.mergeKey == mergeKey,
               now.timeIntervalSince(last.recordedAt) < Self.mergeWindow {
                // The step that is there already goes back to before all of it.
                undoSteps[undoSteps.count - 1].recordedAt = now
                isGrouping = true
                return
            }
            add(actions, name: name, tag: tag, mergeKey: mergeKey, to: \.undoSteps)
        case .undoing:
            add(actions, name: running?.name ?? name, tag: tag, mergeKey: nil, to: \.redoSteps)
        case .redoing:
            add(actions, name: running?.name ?? name, tag: tag, mergeKey: nil, to: \.undoSteps)
        }
    }

    private mutating func add(
        _ actions: [Action], name: LocalizedStringResource, tag: UUID?, mergeKey: String?, to side: WritableKeyPath<Self, [Step]>
    ) {
        if isGrouping, !self[keyPath: side].isEmpty {
            let last = self[keyPath: side].count - 1
            self[keyPath: side][last].actions.insert(contentsOf: actions, at: 0)
            if let tag { self[keyPath: side][last].tag = tag }
        } else {
            self[keyPath: side].append(Step(name: name, actions: actions, tag: tag, mergeKey: mergeKey))
            if self[keyPath: side].count > Self.limit { self[keyPath: side].removeFirst() }
            isGrouping = true
        }
    }

    /// The moment is over: what is recorded next is a step of its own.
    mutating func endGroup() {
        if mode == .recording { isGrouping = false }
    }

    /// Lets the step just recorded answer to a notice's Undo. False when this moment recorded none.
    @discardableResult
    mutating func tagLastStep(_ tag: UUID) -> Bool {
        guard mode == .recording, isGrouping, !undoSteps.isEmpty else { return false }
        undoSteps[undoSteps.count - 1].tag = tag
        return true
    }

    /// Takes the step to run next off its side; a notice's Undo names its own, which may lie further back.
    mutating func take(_ mode: Mode, tag: UUID? = nil) -> Step? {
        if mode == .undoing {
            guard let tag else { return undoSteps.popLast() }
            return undoSteps.firstIndex { $0.tag == tag }.map { undoSteps.remove(at: $0) }
        }
        return mode == .redoing ? redoSteps.popLast() : nil
    }

    mutating func begin(_ mode: Mode, _ step: Step) {
        self.mode = mode
        running = step
        isGrouping = false
    }

    /// Whether the step did anything, which shows in having left its opposite behind.
    mutating func finish() -> Bool {
        let didSomething = isGrouping
        mode = .recording
        running = nil
        isGrouping = false
        return didSomething
    }

    /// Forgets a step that can't be taken back any more, on either side.
    mutating func remove(tag: UUID) {
        undoSteps.removeAll { $0.tag == tag }
        redoSteps.removeAll { $0.tag == tag }
    }
}
