import Foundation

/// The result of a finished workout, after it has been saved to HealthKit.
struct CompletedWorkout: Equatable, Sendable {
    let start: Date
    let end: Date
    let distanceMeters: Double
    let activeEnergyKcal: Double
    let averageHeartRate: Double?
    let splits: [Split]

    var duration: TimeInterval { end.timeIntervalSince(start) }

    var averagePaceSecPerKm: Double? {
        guard distanceMeters > 0 else { return nil }
        return duration / (distanceMeters / 1000)
    }
}
