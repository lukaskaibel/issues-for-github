import Foundation
import Testing
@testable import GitIssuesKit

@Suite("Timeline zoom")
struct TimelineZoomTests {
    @Test("A saved number or launch-argument string both set a custom scale", arguments: [false, true])
    func readsStoredScale(asString: Bool) throws {
        let suite = "TimelineZoomTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(TimelineZoom.storedScale(in: defaults) == nil)
        if asString { defaults.set("7.5", forKey: "timeline.scale") }
        else { defaults.set(7.5, forKey: "timeline.scale") }
        #expect(TimelineZoom.storedScale(in: defaults) == 7.5)
    }

    @Test("Every input stays inside the same zoom limits")
    func clampsAllInputs() {
        #expect(TimelineZoom.clamp(0.01) == 1)
        #expect(TimelineZoom.clamp(100) == 40)
        #expect(TimelineZoom.clamp(.infinity) == 40)
        #expect(TimelineZoom.clamp(-.infinity) == 1)
        #expect(TimelineZoom.clamp(.nan) == RoadmapZoom.months.scale)
        #expect(TimelineZoom.clamp(RoadmapZoom.months.scale) == RoadmapZoom.months.scale)
        #expect(TimelineZoom.clamp(RoadmapZoom.quarters.scale) == RoadmapZoom.quarters.scale)
    }

    @Test("Repeated button and key presses stop at each limit and reverse immediately")
    func boundsSteps() {
        var scale: CGFloat = RoadmapZoom.months.scale
        for _ in 0..<100 { scale = TimelineZoom.stepped(scale, by: 1) }
        #expect(scale == 40)
        #expect(TimelineZoom.stepped(scale, by: -1) == 32)
        for _ in 0..<100 { scale = TimelineZoom.stepped(scale, by: -1) }
        #expect(scale == 1)
        #expect(TimelineZoom.stepped(scale, by: 1) == 1.25)
    }

    @Test("Zoom preserves the day under the pointer or viewport centre")
    func anchorsDay() {
        let oldOffset: CGFloat = 300
        let anchor: CGFloat = 120
        let next = TimelineZoom.offset(oldOffset, anchor: anchor, from: 5, to: 10)
        #expect(next == 720)
        #expect((oldOffset + anchor) / 5 == (next + anchor) / 10)
        #expect(TimelineZoom.offset(next, anchor: anchor, from: 10, to: 5) == oldOffset)
    }

    @Test("A zoom near the beginning never asks to scroll before the first day")
    func clipsLeadingEdge() {
        #expect(TimelineZoom.offset(0, anchor: 200, from: 5, to: 1) == 0)
    }
}
