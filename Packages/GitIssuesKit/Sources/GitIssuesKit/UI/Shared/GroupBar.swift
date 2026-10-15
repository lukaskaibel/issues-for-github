import SwiftUI

/// A view's group as a bar: done, under way and the rest across the group, or what a person has open as long as their
/// share of the most anyone has, under way first. The Mac's list draws the same in its headers (`GroupBars`).
struct GroupBar: View {
    var style: GroupStyle
    var progress: GroupProgress
    var share: CGFloat
    var width: CGFloat

    var body: some View {
        let total = CGFloat(max(progress.total, 1))
        Group {
            switch style {
            case .progress:
                HStack(spacing: 0) {
                    Rectangle().fill(Theme.positive).frame(width: width * CGFloat(progress.done) / total)
                    Rectangle().fill(Theme.started).frame(width: width * CGFloat(progress.started) / total)
                    Spacer(minLength: 0)
                }
                .frame(width: width, height: 6)
                .background(Theme.textTertiary.opacity(0.22))
                .clipShape(Capsule())
            case .people:
                let open = CGFloat(progress.total - progress.done)
                let length = open > 0 ? max(6, width * min(max(share, 0), 1)) : 0
                HStack(spacing: 0) {
                    Rectangle().fill(Theme.started).frame(width: open > 0 ? length * CGFloat(progress.started) / open : 0)
                    Spacer(minLength: 0)
                }
                .frame(width: length, height: 6)
                .background(Theme.textTertiary.opacity(0.35))
                .clipShape(Capsule())
                .frame(width: width, alignment: .trailing)
            case .plain:
                EmptyView()
            }
        }
        .accessibilityHidden(true)
    }
}

/// Over a view that shows one iteration, as Linear's cycles: which one, when, how far its issues are, and arrows to
/// the one before and after. The arrows change the view's filter, here only until it is saved.
struct CycleHeader: View {
    @Environment(AppModel.self) private var model
    var view: ProjectView
    var pinned: PinnedIteration
    var compact = false

    var body: some View {
        let progress = model.progress(of: model.items(of: view))
        let current = pinned.iteration.contains(.today())
        HStack(spacing: compact ? 8 : 12) {
            IterationIcon(size: 14)
                .foregroundStyle(current ? Theme.started : Theme.textSecondary)
            Text(pinned.iteration.title)
                .font(compact ? .footnote.weight(.semibold) : .uiSemibold)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            if !compact, let range = model.iterationRange(pinned.iteration) {
                Text(range).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            if let timing = model.iterationTiming(pinned.iteration) {
                Text(timing).foregroundStyle(Theme.textTertiary).lineLimit(1)
            }
            if progress.total > 0 {
                GroupBar(style: .progress, progress: progress, share: 1, width: compact ? 48 : 120)
                Text(progress.fraction)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
                    .accessibilityLabel(Text(.milestoneProgressTooltip(done: progress.done, total: progress.total)))
            }
            Spacer(minLength: 4)
            step(-1, to: pinned.previous)
            step(1, to: pinned.next)
        }
        .font(compact ? .footnote : .ui)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cycle")
    }

    @ViewBuilder
    private func step(_ delta: Int, to iteration: IterationSpan?) -> some View {
        Button {
            withAnimation(Theme.spring) { model.stepIteration(of: view, by: delta) }
        } label: {
            HStack(spacing: 4) {
                if delta < 0 { Image(systemName: "chevron.left").font(.system(size: 9, weight: .bold)) }
                if !compact { Text(iteration?.title ?? "").lineLimit(1) }
                if delta > 0 { Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)) }
            }
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, compact ? 8 : 9)
            .frame(height: compact ? 28 : 24)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.chipBorder, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(iteration == nil)
        .opacity(iteration == nil ? 0.4 : 1)
        .accessibilityLabel(Text(delta < 0 ? .previousIteration : .nextIteration))
        .accessibilityValue(iteration?.title ?? "")
        .accessibilityIdentifier(delta < 0 ? "cycle-previous" : "cycle-next")
        .help(iteration?.title ?? "")
    }
}
