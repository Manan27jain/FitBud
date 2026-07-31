import Foundation

/// One work or recovery period inside a repeat block.
struct Interval: Equatable, Sendable {
    let minutes: Double
    let zone: String
    let label: String

    init(minutes: Double, zone: String, label: String = "") {
        self.minutes = minutes
        self.zone = zone
        self.label = label
    }
}

/// The shape of a session. Mirrors the `segments` array in the plan JSON,
/// which Stage 2 will decode directly into this type.
enum WorkoutSegment: Equatable, Sendable {
    case warmup(minutes: Double, zone: String, label: String)
    case cooldown(minutes: Double, zone: String, label: String)
    case repeatBlock(times: Int, work: Interval, recover: Interval)
    /// Easy and long runs have no structure — they run until you stop.
    case openEnded(zone: String, label: String)
}
