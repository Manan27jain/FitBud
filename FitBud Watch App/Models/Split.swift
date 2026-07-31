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
    /// The heart rate sampled *at* the kilometre boundary, not a mean across the
    /// kilometre. Averaging would need per-split accumulation the engine does
    /// not do yet; Stage 2 can add it if a true mean turns out to be wanted.
    let heartRateAtSplit: Double?

    /// Pace for this split in seconds per kilometre.
    var paceSecPerKm: Double {
        guard distanceMeters > 0 else { return 0 }
        return duration / (distanceMeters / 1000)
    }
}
