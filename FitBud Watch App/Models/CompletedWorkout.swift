import Foundation

/// The result of a finished workout, after it has been saved to HealthKit.
struct CompletedWorkout: Equatable, Sendable {
    let start: Date
    let end: Date
    /// Time spent working out, **excluding** time spent paused — taken from the
    /// saved `HKWorkout` rather than `end - start`. Wall-clock arithmetic would
    /// count a three-minute traffic-light pause and make the summary's average
    /// pace contradict the splits listed directly above it, which come from the
    /// builder's elapsed time.
    let duration: TimeInterval
    let distanceMeters: Double
    let activeEnergyKcal: Double
    let averageHeartRate: Double?
    let splits: [Split]

    var averagePaceSecPerKm: Double? {
        guard distanceMeters > 0, duration > 0 else { return nil }
        return duration / (distanceMeters / 1000)
    }
}
