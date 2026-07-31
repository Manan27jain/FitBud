import Foundation

/// An immutable snapshot of sensor values at one instant of a workout.
/// Produced by `WorkoutRecording`, consumed by `WorkoutEngine`.
struct LiveMetrics: Equatable, Sendable {
    /// Seconds since the workout started, excluding time spent paused.
    var elapsed: TimeInterval
    var distanceMeters: Double
    /// `nil` until the first heart-rate sample arrives.
    var heartRate: Double?
    var activeEnergyKcal: Double

    init(
        elapsed: TimeInterval,
        distanceMeters: Double = 0,
        heartRate: Double? = nil,
        activeEnergyKcal: Double = 0
    ) {
        self.elapsed = elapsed
        self.distanceMeters = distanceMeters
        self.heartRate = heartRate
        self.activeEnergyKcal = activeEnergyKcal
    }
}
