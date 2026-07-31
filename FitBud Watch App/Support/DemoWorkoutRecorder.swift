#if DEBUG
import Foundation

/// A fake recorder that plays a scripted workout, for looking at the UI on a
/// simulator that has no heart-rate sensor.
///
/// The heart rate sweeps 130 → 200 bpm and back, so every zone is entered in
/// turn and the ring, scale and zone bar can all be seen doing their job.
/// Compiled out of release builds entirely.
@MainActor
final class DemoWorkoutRecorder: WorkoutRecording {
    private var continuation: AsyncThrowingStream<LiveMetrics, Error>.Continuation?
    private var task: Task<Void, Never>?
    private var elapsed: TimeInterval = 0
    private var distance: Double = 0
    private var isPaused = false

    /// Seconds of simulated workout per real second. The sweep covers all five
    /// zones in about half a minute of watching.
    private let timeScale: Double = 20

    func start(_ configuration: WorkoutConfiguration) async throws -> AsyncThrowingStream<LiveMetrics, Error> {
        let stream = AsyncThrowingStream<LiveMetrics, Error> { continuation in
            self.continuation = continuation
        }
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, !self.isPaused else { continue }
                self.elapsed += self.timeScale / 2
                // Roughly 9:00/km, the athlete's target easy pace.
                self.distance += (self.timeScale / 2) * (1000.0 / 540.0)
                self.continuation?.yield(
                    LiveMetrics(
                        elapsed: self.elapsed,
                        distanceMeters: self.distance,
                        heartRate: Self.scriptedHeartRate(at: self.elapsed),
                        activeEnergyKcal: self.elapsed * 0.16
                    )
                )
            }
        }
        return stream
    }

    /// Triangle wave from 130 to 200 bpm over a 20-minute period, so the needle
    /// climbs through every zone and comes back down.
    nonisolated static func scriptedHeartRate(at elapsed: TimeInterval) -> Double {
        let period: Double = 1_200
        let position = elapsed.truncatingRemainder(dividingBy: period) / period
        let triangle = position < 0.5 ? position * 2 : (1 - position) * 2
        return 130 + triangle * 70
    }

    func pause() async throws { isPaused = true }
    func resume() async throws { isPaused = false }

    func end(splits: [Split]) async throws -> CompletedWorkout {
        task?.cancel()
        continuation?.finish()
        let end = Date()
        return CompletedWorkout(
            start: end.addingTimeInterval(-elapsed),
            end: end,
            duration: elapsed,
            distanceMeters: distance,
            activeEnergyKcal: elapsed * 0.16,
            averageHeartRate: 158,
            splits: splits
        )
    }
}
#endif
