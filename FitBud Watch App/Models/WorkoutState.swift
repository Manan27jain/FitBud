import Foundation

/// Everything the live workout screen renders. Derived entirely from the
/// metric stream — the UI holds no workout logic of its own.
struct WorkoutState: Equatable, Sendable {
    var elapsed: TimeInterval = 0
    var distanceMeters: Double = 0
    var heartRate: Double?
    var activeEnergyKcal: Double = 0

    var currentBlock: TimelineBlock?
    var currentBlockIndex: Int?
    var blockRemaining: TimeInterval?

    var runWalkPhase: RunWalkPhase?
    var phaseRemaining: TimeInterval?

    var splits: [Split] = []
    var isComplete = false

    /// Average pace across the whole workout so far, seconds per kilometre.
    var averagePaceSecPerKm: Double? {
        guard distanceMeters > 0 else { return nil }
        return elapsed / (distanceMeters / 1000)
    }

    var distanceKm: Double { distanceMeters / 1000 }
}
