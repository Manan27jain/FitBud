import Foundation

enum WorkoutEvent: Equatable, Sendable {
    case splitCompleted(Split)
    case phaseChanged(RunWalkPhase)
    case blockChanged(index: Int, block: TimelineBlock)
    /// A fixed-length session has run past its final block.
    case finished
}

/// Turns a stream of sensor snapshots into workout state and discrete events.
///
/// Pure and deterministic: the same sequence of `LiveMetrics` always yields the
/// same events, which is what makes it testable without a watch on a wrist.
struct WorkoutEngine {
    private let timeline: SegmentTimeline
    private let runWalk: RunWalkCycler?

    private var splitDetector = SplitDetector()
    private var lastPhase: RunWalkPhase?
    private var lastBlockIndex: Int?
    private var hasFinished = false
    private var lastElapsed: TimeInterval?
    private var heartRateSum: Double = 0
    private var heartRateCount: Int = 0

    private(set) var state = WorkoutState()

    init(timeline: SegmentTimeline, runWalk: RunWalkCycler?) {
        self.timeline = timeline
        self.runWalk = runWalk
    }

    /// Feeds one sensor snapshot in and returns everything that changed because
    /// of it. Order is stable: splits, then phase change, then block change,
    /// then completion.
    mutating func ingest(_ metrics: LiveMetrics) -> [WorkoutEvent] {
        state.elapsed = metrics.elapsed
        state.distanceMeters = metrics.distanceMeters
        state.heartRate = metrics.heartRate
        state.activeEnergyKcal = metrics.activeEnergyKcal

        // Whether this sample is new information. The recorder ticks at 1 Hz
        // whether or not the session is paused, but `elapsed` comes from the
        // workout builder and excludes paused time — so during a pause the
        // same instant is re-reported once a second, carrying a stale heart
        // rate with it. The first sample of a workout has nothing to compare
        // against and counts.
        let advancesTime = lastElapsed.map { metrics.elapsed > $0 } ?? true

        // Attribute the interval since the previous sample to the zone the
        // athlete is in now. A sample with no heart rate is attributed to
        // nothing at all rather than being guessed at — a fabricated zone would
        // corrupt the one number the training plan is judged on.
        if let bpm = metrics.heartRate {
            // `currentZone` and `state.heartRate` above update regardless: a
            // paused athlete looking at the watch should still see their live
            // heart rate. It is only the accumulators below that a repeated
            // instant must not touch.
            let zone = HRZone.zone(for: bpm)
            state.currentZone = zone
            if advancesTime {
                if let zone, let last = lastElapsed {
                    state.timeInZone[zone.id, default: 0] += metrics.elapsed - last
                }
                // Outside this guard, a ten-minute pause folded ~600 copies of
                // one stale reading into the average shown on the Zones page,
                // dragging it toward whatever the athlete's heart happened to
                // be doing when they stopped.
                heartRateSum += bpm
                heartRateCount += 1
                state.averageHeartRate = heartRateSum / Double(heartRateCount)
            }
        } else {
            state.currentZone = nil
        }
        lastElapsed = metrics.elapsed

        var events: [WorkoutEvent] = []

        let splits = splitDetector.update(
            distanceMeters: metrics.distanceMeters,
            elapsed: metrics.elapsed,
            heartRate: metrics.heartRate
        )
        state.splits = splitDetector.splits
        events.append(contentsOf: splits.map(WorkoutEvent.splitCompleted))

        if let runWalk {
            let phase = runWalk.phase(at: metrics.elapsed)
            state.runWalkPhase = phase
            state.phaseRemaining = runWalk.remainingInPhase(at: metrics.elapsed)
            state.phaseRemainingFraction = runWalk.remainingFraction(at: metrics.elapsed)
            if phase != lastPhase {
                if lastPhase != nil { events.append(.phaseChanged(phase)) }
                lastPhase = phase
            }
        }

        if let position = timeline.position(at: metrics.elapsed) {
            state.currentBlock = position.block
            state.currentBlockIndex = position.index
            state.blockRemaining = position.remaining
            if position.index != lastBlockIndex {
                events.append(.blockChanged(index: position.index, block: position.block))
                lastBlockIndex = position.index
            }
        } else if !hasFinished {
            // A fixed-length session ran past its final block.
            hasFinished = true
            state.isComplete = true
            state.currentBlock = nil
            state.currentBlockIndex = nil
            state.blockRemaining = nil
            events.append(.finished)
        }

        return events
    }
}
