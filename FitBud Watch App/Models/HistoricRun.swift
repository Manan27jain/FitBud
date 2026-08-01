import Foundation

/// A completed run read back out of HealthKit, for the home screen's history.
struct HistoricRun: Identifiable, Equatable, Sendable {
    let id: UUID
    let date: Date
    let distanceMeters: Double
    let duration: TimeInterval
    let averageHeartRate: Double?

    var distanceKm: Double { distanceMeters / 1000 }

    var paceSecPerKm: Double? {
        guard distanceMeters > 0, duration > 0 else { return nil }
        return duration / (distanceMeters / 1000)
    }

    /// The zone this run's *average* heart rate falls in. A single average is a
    /// blunt instrument — a run can average Z2 while spending time either side —
    /// but it is what HealthKit stores per workout, and it is honest about the
    /// question the home screen asks: was this run easy or not?
    var zone: HRZone? {
        averageHeartRate.flatMap(HRZone.zone(for:))
    }

    /// Whether this counts toward the plan's 80%-easy rule.
    ///
    /// `zone` is nil for two completely different reasons, and collapsing them
    /// into "not easy" made the home screen tell the athlete the opposite of
    /// the truth about the most compliant run he can produce:
    ///
    /// - **No heart rate at all.** Not easy, deliberately. An unmeasured run
    ///   says nothing about effort and must not flatter the one number the
    ///   whole plan is judged on.
    /// - **A heart rate below Z1's 133 bpm floor** — a recovery jog averaging
    ///   130. `HRZone.zone(for:)` is right to return nil there (a resting 62
    ///   genuinely is not a training zone), but for *this* question it is
    ///   emphatically easy: the 80% rule only asks whether the run stayed
    ///   under the easy ceiling, and this is as far under it as running gets.
    var isEasy: Bool {
        guard let averageHeartRate else { return false }
        guard let zone = HRZone.zone(for: averageHeartRate) else { return true }
        return zone.id == "Z1" || zone.id == "Z2"
    }
}
