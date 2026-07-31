import Testing
@testable import FitBud_Watch_App

struct WorkoutEngineTests {
    /// A long run: open-ended, 4:1 run/walk.
    private func longRunEngine() -> WorkoutEngine {
        WorkoutEngine(
            timeline: SegmentTimeline(segments: [.openEnded(zone: "Z2", label: "Long run")]),
            runWalk: RunWalkCycler(runSeconds: 240, walkSeconds: 60)
        )
    }

    @Test func firstUpdateAnnouncesTheStartingBlock() {
        var engine = longRunEngine()
        let events = engine.ingest(LiveMetrics(elapsed: 0))
        #expect(events.contains { if case .blockChanged(0, _) = $0 { return true }; return false })
    }

    @Test func stateTracksTheLatestMetrics() {
        var engine = longRunEngine()
        _ = engine.ingest(LiveMetrics(elapsed: 60, distanceMeters: 180, heartRate: 152, activeEnergyKcal: 14))
        #expect(engine.state.elapsed == 60)
        #expect(engine.state.distanceMeters == 180)
        #expect(engine.state.heartRate == 152)
        #expect(engine.state.activeEnergyKcal == 14)
    }

    @Test func emitsPhaseChangeWhenTheWalkBreakStarts() {
        var engine = longRunEngine()
        _ = engine.ingest(LiveMetrics(elapsed: 239, distanceMeters: 700))
        let events = engine.ingest(LiveMetrics(elapsed: 241, distanceMeters: 705))
        #expect(events.contains(.phaseChanged(.walk)))
        #expect(engine.state.runWalkPhase == .walk)
    }

    @Test func doesNotRepeatThePhaseChangeWithinTheSamePhase() {
        var engine = longRunEngine()
        _ = engine.ingest(LiveMetrics(elapsed: 241, distanceMeters: 705))
        let events = engine.ingest(LiveMetrics(elapsed: 250, distanceMeters: 720))
        #expect(!events.contains(.phaseChanged(.walk)))
    }

    @Test func emitsSplitWhenAKilometreCompletes() {
        var engine = longRunEngine()
        let events = engine.ingest(LiveMetrics(elapsed: 540, distanceMeters: 1000, heartRate: 158))
        let splits = events.compactMap { event -> Split? in
            if case let .splitCompleted(split) = event { return split }
            return nil
        }
        #expect(splits.count == 1)
        #expect(splits[0].index == 1)
        #expect(engine.state.splits.count == 1)
    }

    @Test func averagePaceIsDerivedFromElapsedAndDistance() {
        var engine = longRunEngine()
        _ = engine.ingest(LiveMetrics(elapsed: 540, distanceMeters: 1000))
        #expect(engine.state.averagePaceSecPerKm == 540)
    }

    @Test func averagePaceIsNilBeforeAnyDistance() {
        var engine = longRunEngine()
        _ = engine.ingest(LiveMetrics(elapsed: 10, distanceMeters: 0))
        #expect(engine.state.averagePaceSecPerKm == nil)
    }

    @Test func structuredSessionAdvancesThroughItsBlocks() {
        var engine = WorkoutEngine(
            timeline: SegmentTimeline(segments: [
                .warmup(minutes: 10, zone: "Z1", label: "Warm up"),
                .repeatBlock(
                    times: 2,
                    work: Interval(minutes: 3, zone: "Z4", label: "Threshold"),
                    recover: Interval(minutes: 2, zone: "Z1", label: "Jog")
                ),
                .cooldown(minutes: 10, zone: "Z1", label: "Cool down")
            ]),
            runWalk: nil
        )
        _ = engine.ingest(LiveMetrics(elapsed: 0))
        let intoWork = engine.ingest(LiveMetrics(elapsed: 601))
        #expect(intoWork.contains { if case .blockChanged(1, _) = $0 { return true }; return false })
        #expect(engine.state.currentBlock?.kind == .work)
    }

    @Test func structuredSessionFinishesAfterItsLastBlock() {
        var engine = WorkoutEngine(
            timeline: SegmentTimeline(segments: [.warmup(minutes: 1, zone: "Z1", label: "Warm up")]),
            runWalk: nil
        )
        _ = engine.ingest(LiveMetrics(elapsed: 0))
        let events = engine.ingest(LiveMetrics(elapsed: 61))
        #expect(events.contains(.finished))
        #expect(engine.state.isComplete)
    }

    @Test func openEndedSessionNeverFinishesOnItsOwn() {
        var engine = longRunEngine()
        let events = engine.ingest(LiveMetrics(elapsed: 7_200, distanceMeters: 14_000))
        #expect(!events.contains(.finished))
        #expect(!engine.state.isComplete)
    }

    @Test func noRunWalkMeansNoPhaseEvents() {
        var engine = WorkoutEngine(
            timeline: SegmentTimeline(segments: [.openEnded(zone: "Z2", label: "Easy")]),
            runWalk: nil
        )
        let events = engine.ingest(LiveMetrics(elapsed: 300, distanceMeters: 900))
        #expect(!events.contains { if case .phaseChanged = $0 { return true }; return false })
        #expect(engine.state.runWalkPhase == nil)
    }
}
