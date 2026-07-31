import Foundation

/// Detects kilometre boundaries in a monotonically increasing distance stream.
/// Pure: no clock, no sensors, no HealthKit.
struct SplitDetector {
    let intervalMeters: Double

    private(set) var splits: [Split] = []
    private var lastSplitElapsed: TimeInterval = 0

    init(intervalMeters: Double = 1000) {
        self.intervalMeters = intervalMeters
    }

    /// Feeds the latest cumulative distance in.
    /// Returns every split completed by this update, in order — usually none or one,
    /// but more if the distance reading jumped across several boundaries at once.
    mutating func update(
        distanceMeters: Double,
        elapsed: TimeInterval,
        heartRate: Double?
    ) -> [Split] {
        let completed = Int(distanceMeters / intervalMeters)
        guard completed > splits.count else { return [] }

        var emitted: [Split] = []
        // Interpolate evenly across the boundaries this update crossed. With a
        // single boundary this is exact; with several it apportions the elapsed
        // time between them, which is the best available estimate.
        let spanStart = lastSplitElapsed
        let spanDuration = elapsed - spanStart
        let crossings = completed - splits.count

        for step in 1...crossings {
            let splitElapsed = spanStart + spanDuration * (Double(step) / Double(crossings))
            let index = splits.count + 1
            let split = Split(
                index: index,
                distanceMeters: intervalMeters,
                elapsed: splitElapsed,
                duration: splitElapsed - lastSplitElapsed,
                heartRateAtSplit: heartRate
            )
            splits.append(split)
            emitted.append(split)
            lastSplitElapsed = splitElapsed
        }
        return emitted
    }
}
