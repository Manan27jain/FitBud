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
    var isEasy: Bool {
        guard let zone else { return false }
        return zone.id == "Z1" || zone.id == "Z2"
    }
}
