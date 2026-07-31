import Foundation

enum BlockKind: Equatable, Sendable {
    case warmup
    case work
    case recover
    case cooldown
    /// Runs until the athlete stops. Has no duration.
    case open
}

/// One concrete, indivisible period of a session.
struct TimelineBlock: Equatable, Sendable {
    let kind: BlockKind
    /// `nil` for open-ended blocks.
    let duration: TimeInterval?
    let zone: String
    let label: String
}

/// Flattens a session's segments into an ordered list of blocks the engine can
/// index by elapsed time. A repeat block becomes its expanded repetitions.
struct SegmentTimeline: Equatable, Sendable {
    struct Position: Equatable {
        let index: Int
        let block: TimelineBlock
        /// `nil` when the block is open-ended.
        let remaining: TimeInterval?
    }

    let blocks: [TimelineBlock]

    init(segments: [WorkoutSegment]) {
        var blocks: [TimelineBlock] = []
        for segment in segments {
            switch segment {
            case let .warmup(minutes, zone, label):
                blocks.append(TimelineBlock(kind: .warmup, duration: minutes * 60, zone: zone, label: label))
            case let .cooldown(minutes, zone, label):
                blocks.append(TimelineBlock(kind: .cooldown, duration: minutes * 60, zone: zone, label: label))
            case let .repeatBlock(times, work, recover):
                for _ in 0..<times {
                    blocks.append(TimelineBlock(kind: .work, duration: work.minutes * 60, zone: work.zone, label: work.label))
                    blocks.append(TimelineBlock(kind: .recover, duration: recover.minutes * 60, zone: recover.zone, label: recover.label))
                }
            case let .openEnded(zone, label):
                blocks.append(TimelineBlock(kind: .open, duration: nil, zone: zone, label: label))
            }
        }
        self.blocks = blocks
    }

    /// `nil` if any block is open-ended — such a session has no fixed length.
    var totalDuration: TimeInterval? {
        var total: TimeInterval = 0
        for block in blocks {
            guard let duration = block.duration else { return nil }
            total += duration
        }
        return total
    }

    /// Which block the workout is in at `elapsed`, and how much of it is left.
    /// Returns `nil` once a fixed-length session has finished.
    func position(at elapsed: TimeInterval) -> Position? {
        var start: TimeInterval = 0
        for (index, block) in blocks.enumerated() {
            guard let duration = block.duration else {
                return Position(index: index, block: block, remaining: nil)
            }
            let end = start + duration
            if elapsed < end {
                return Position(index: index, block: block, remaining: end - elapsed)
            }
            start = end
        }
        return nil
    }
}
