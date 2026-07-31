import Testing
@testable import FitBud_Watch_App

struct SegmentTimelineTests {
    /// Week 5 Thursday: 10min warmup, 5x(3min Z4 / 2min jog), 10min cooldown.
    let intervals = SegmentTimeline(segments: [
        .warmup(minutes: 10, zone: "Z1", label: "Warm up"),
        .repeatBlock(
            times: 5,
            work: Interval(minutes: 3, zone: "Z4", label: "3min threshold"),
            recover: Interval(minutes: 2, zone: "Z1", label: "2min jog")
        ),
        .cooldown(minutes: 10, zone: "Z1", label: "Cool down")
    ])

    @Test func repeatBlocksAreFlattenedIntoDiscreteBlocks() {
        // warmup + (work + recover) * 5 + cooldown
        #expect(intervals.blocks.count == 12)
        #expect(intervals.blocks[0].kind == .warmup)
        #expect(intervals.blocks[1].kind == .work)
        #expect(intervals.blocks[2].kind == .recover)
        #expect(intervals.blocks[10].kind == .recover)
        #expect(intervals.blocks[11].kind == .cooldown)
    }

    @Test func totalDurationSumsEveryBlock() {
        // 10 + 5*(3+2) + 10 = 45 minutes
        #expect(intervals.totalDuration == Double(45 * 60))
    }

    @Test func positionResolvesToTheWarmupAtTheStart() {
        let position = intervals.position(at: 0)
        #expect(position?.index == 0)
        #expect(position?.block.kind == .warmup)
        #expect(position?.remaining == 600)
    }

    @Test func positionCrossesIntoTheFirstWorkInterval() {
        let position = intervals.position(at: 600)
        #expect(position?.index == 1)
        #expect(position?.block.kind == .work)
        #expect(position?.block.zone == "Z4")
        #expect(position?.remaining == 180)
    }

    @Test func positionResolvesMidWorkout() {
        // 600 warmup + 180 work + 120 recover = 900s -> second work interval
        let position = intervals.position(at: 900)
        #expect(position?.index == 3)
        #expect(position?.block.kind == .work)
    }

    @Test func positionIsNilPastTheEnd() {
        #expect(intervals.position(at: 45 * 60 + 1) == nil)
    }

    @Test func openEndedSessionsHaveOneBlockAndNoTotalDuration() {
        let easy = SegmentTimeline(segments: [.openEnded(zone: "Z2", label: "Easy run")])
        #expect(easy.blocks.count == 1)
        #expect(easy.blocks[0].kind == .open)
        #expect(easy.blocks[0].duration == nil)
        #expect(easy.totalDuration == nil)
    }

    @Test func openEndedPositionNeverExpires() {
        let easy = SegmentTimeline(segments: [.openEnded(zone: "Z2", label: "Easy run")])
        let position = easy.position(at: 9_999)
        #expect(position?.index == 0)
        #expect(position?.remaining == nil)
    }
}
