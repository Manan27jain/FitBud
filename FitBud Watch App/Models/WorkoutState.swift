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

    /// The zone the latest heart-rate sample falls in, or `nil` when there is no
    /// sample or it is below the lowest training zone.
    var currentZone: HRZone?

    /// Seconds spent in each zone, keyed by `HRZone.id`. Only intervals with a
    /// heart-rate sample are attributed, so this can total less than `elapsed`.
    var timeInZone: [String: TimeInterval] = [:]

    /// Running mean of the heart-rate samples seen so far. This is for live
    /// display only — `CompletedWorkout.averageHeartRate` uses HealthKit's own
    /// time-weighted average, which is the authoritative figure.
    var averageHeartRate: Double?

    /// Fraction of the current run/walk phase still remaining, 1 → 0. `nil` for
    /// sessions with no run/walk configured.
    var phaseRemainingFraction: Double?

    var splits: [Split] = []
    var isComplete = false

    /// Average pace across the whole workout so far, seconds per kilometre.
    var averagePaceSecPerKm: Double? {
        guard distanceMeters > 0 else { return nil }
        return elapsed / (distanceMeters / 1000)
    }

    var distanceKm: Double { distanceMeters / 1000 }
}
