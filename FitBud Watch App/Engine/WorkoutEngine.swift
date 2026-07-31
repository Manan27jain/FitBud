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
