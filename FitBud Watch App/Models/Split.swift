import Foundation

/// One completed kilometre.
struct Split: Equatable, Sendable {
    /// 1-based: the first kilometre is index 1.
    let index: Int
    let distanceMeters: Double
    /// Cumulative elapsed time at the moment this split completed.
    let elapsed: TimeInterval
    /// Time taken for this split alone.
    let duration: TimeInterval
    let averageHeartRate: Double?

    /// Pace for this split in seconds per kilometre.
    var paceSecPerKm: Double {
        guard distanceMeters > 0 else { return 0 }
        return duration / (distanceMeters / 1000)
    }
}
