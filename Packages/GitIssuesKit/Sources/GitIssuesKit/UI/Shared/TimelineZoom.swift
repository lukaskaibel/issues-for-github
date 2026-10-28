import SwiftUI
#if os(macOS)
import AppKit
#endif

/// The same bounds apply to presets, gestures, buttons and keys, in points per calendar day.
enum TimelineZoom {
    static let minimumScale: CGFloat = 1
    static let maximumScale: CGFloat = 40
    static let step: CGFloat = 1.25

    static func clamp(_ scale: CGFloat) -> CGFloat {
        guard !scale.isNaN else { return RoadmapZoom.months.scale }
        return min(max(scale, minimumScale), maximumScale)
    }

    static func stepped(_ scale: CGFloat, by steps: Int) -> CGFloat {
        clamp(clamp(scale) * pow(step, CGFloat(steps)))
    }

    /// Keep the day beneath the pointer (or the viewport's centre for buttons and keys) in the same place.
    static func offset(_ offset: CGFloat, anchor: CGFloat, from oldScale: CGFloat, to newScale: CGFloat) -> CGFloat {
        max(0, (offset + anchor) / clamp(oldScale) * clamp(newScale) - anchor)
    }
}

extension AppModel {
    var timelineScale: CGFloat { TimelineZoom.clamp(timelineScaleOverride.map { CGFloat($0) } ?? roadmapZoom.scale) }

    func setTimelineScale(_ scale: CGFloat) {
        guard !isDragging else { return }
        let scale = TimelineZoom.clamp(scale)
        if scale != timelineScale { timelineScaleOverride = Double(scale) }
    }

    func zoomTimeline(by steps: Int) {
        setTimelineScale(TimelineZoom.stepped(timelineScale, by: steps))
    }

    func resetTimelineZoom() { timelineScaleOverride = nil }

    var showsTimelineCanvas: Bool {
        guard openItem == nil else { return false }
        if case .roadmap = scope { return roadmapLayout == .timeline }
        return currentView.map(showsTimeline) ?? false
    }
}

extension View {
    /// Apply directly to the horizontal ScrollView, so its viewport anchors the zoom and normal scrolling stays native.
    func timelineZoom(scale: CGFloat) -> some View {
        modifier(TimelineZoomModifier(scale: scale))
    }
}

private struct TimelineViewport: Equatable {
    var offset: CGFloat = 0
    var width: CGFloat = 0
}

private struct TimelineZoomModifier: ViewModifier {
    @Environment(AppModel.self) private var model
    var scale: CGFloat
    @State private var position = ScrollPosition()
    @State private var viewport = TimelineViewport()
    @State private var pinchScale: CGFloat?
    @State private var anchor: CGFloat?
    @GestureState private var pinching = false

    func body(content: Content) -> some View {
        content
            .scrollPosition($position)
            .onScrollGeometryChange(for: TimelineViewport.self) { geometry in
                TimelineViewport(offset: geometry.contentOffset.x + geometry.contentInsets.leading, width: geometry.containerSize.width)
            } action: { _, next in
                viewport = next
            }
            .onChange(of: scale) { previous, next in
                let offset = TimelineZoom.offset(viewport.offset, anchor: anchor ?? viewport.width / 2, from: previous, to: next)
                viewport.offset = offset
                position.scrollTo(x: offset)
                anchor = nil
            }
            .simultaneousGesture(
                MagnifyGesture()
                    .updating($pinching) { _, active, _ in active = true }
                    .onChanged { value in
                        guard !model.isDragging else { return }
                        if pinchScale == nil { pinchScale = scale }
                        anchor = value.startAnchor.x * viewport.width
                        model.setTimelineScale((pinchScale ?? scale) * value.magnification)
                    }
                    .onEnded { _ in
                        pinchScale = nil
                        anchor = nil
                    }
            )
            .onChange(of: pinching) { _, active in
                if !active {
                    pinchScale = nil
                    anchor = nil
                }
            }
            #if os(macOS)
            .background {
                TimelineWheelZoom(enabled: model.overlay == nil && !model.isDragging && model.openItem == nil) { factor, pointerX in
                    anchor = pointerX
                    model.setTimelineScale(scale * factor)
                }
            }
            #endif
    }
}

/// Small, named buttons also make zoom available to mouse users and VoiceOver.
struct TimelineZoomButtons: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            #if os(macOS)
            ToolbarIconButton(systemImage: "minus.magnifyingglass", label: .timelineZoomOut, help: .timelineZoomOutHelp) {
                model.zoomTimeline(by: -1)
            }
            .disabled(model.timelineScale <= TimelineZoom.minimumScale)
            ToolbarIconButton(systemImage: "plus.magnifyingglass", label: .timelineZoomIn, help: .timelineZoomInHelp) {
                model.zoomTimeline(by: 1)
            }
            .disabled(model.timelineScale >= TimelineZoom.maximumScale)
            #else
            Button { model.zoomTimeline(by: -1) } label: {
                Label(.timelineZoomOut, systemImage: "minus.magnifyingglass")
            }
            .disabled(model.timelineScale <= TimelineZoom.minimumScale)
            Button { model.zoomTimeline(by: 1) } label: {
                Label(.timelineZoomIn, systemImage: "plus.magnifyingglass")
            }
            .disabled(model.timelineScale >= TimelineZoom.maximumScale)
            #endif
        }
    }
}

struct TimelineZoomMenuItems: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button { model.zoomTimeline(by: 1) } label: { Label(.timelineZoomIn, systemImage: "plus.magnifyingglass") }
            .disabled(model.timelineScale >= TimelineZoom.maximumScale)
        Button { model.zoomTimeline(by: -1) } label: { Label(.timelineZoomOut, systemImage: "minus.magnifyingglass") }
            .disabled(model.timelineScale <= TimelineZoom.minimumScale)
        Button(.timelineResetZoom) { model.resetTimelineZoom() }
            .disabled(model.timelineScaleOverride == nil)
    }
}

#if os(macOS)
/// Observe only Command-scroll inside this viewport; all other wheel events retain their usual scrolling behaviour.
private struct TimelineWheelZoom: NSViewRepresentable {
    var enabled: Bool
    var zoom: (CGFloat, CGFloat) -> Void

    func makeNSView(context: Context) -> WheelView { WheelView(enabled: enabled, zoom: zoom) }
    func updateNSView(_ view: WheelView, context: Context) {
        view.enabled = enabled
        view.zoom = zoom
    }

    final class WheelView: NSView {
        var enabled: Bool
        var zoom: (CGFloat, CGFloat) -> Void
        private var monitor: Any?

        init(enabled: Bool, zoom: @escaping (CGFloat, CGFloat) -> Void) {
            self.enabled = enabled
            self.zoom = zoom
            super.init(frame: .zero)
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, self.enabled, let window = self.window, event.window === window, window.isKeyWindow,
                      event.modifierFlags.intersection([.command, .option, .control]) == .command else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(point), event.scrollingDeltaY != 0 else { return event }
                let speed: CGFloat = event.hasPreciseScrollingDeltas ? 0.01 : 0.1
                self.zoom(exp(event.scrollingDeltaY * speed), point.x)
                return nil
            }
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}
#endif
